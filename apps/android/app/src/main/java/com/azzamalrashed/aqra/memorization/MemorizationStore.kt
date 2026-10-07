package com.azzamalrashed.aqra.memorization

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.ProgressJson
import com.azzamalrashed.aqra.curriculum.StagePolicy
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.ReviewPolicy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** What the student has memorized of one ayah, and how firmly. */
@Serializable
data class AyahMemory(
    /**
     * The memorization's half-life in days: how long until the chance of recalling it falls to half. It starts
     * modest for declared ayat, grows with each clean revision and shrinks with each stumble. Files from before
     * revision existed (version 1) don't hold it.
     */
    val stability: Double = ReviewPolicy.STANDARD.declaredStability,
    /** The last revision, or null if it hasn't been revised in Aqra yet (then [since] counts instead). */
    val lastReviewed: Moment? = null,
    /** How many times it was stumbled on in revision. */
    val lapses: Int = 0,
    /** Whether a teacher has confirmed it in a tasmee'. */
    val verified: Boolean = false,
    val since: Moment,
    /** When it was memorized in Aqra as a new portion; null for an ayah the student declared they already knew. */
    val learnedAt: Moment? = null,
    /** The last stumble on it, if any: it's mastered only once a clean revision has come after it. */
    val lastLapseAt: Moment? = null,
) {
    /**
     * Whether it's mastered: established to the stage policy's mastery half-life, with no stumble since its last clean
     * revision.
     */
    fun isMastered(policy: StagePolicy = StagePolicy.STANDARD): Boolean {
        if (stability < policy.masteryStability) return false
        val lapse = lastLapseAt ?: return true
        return (lastReviewed ?: since) > lapse
    }

    /**
     * How strong it is now, from 0 to 1: how established it is (its stability, up to the policy's mature level)
     * times how fresh it is (the chance of recalling it after the days since it was last revised). A just-declared
     * ayah is faint, clean revisions brighten it, and time without revision fades it.
     */
    fun strength(at: Moment, policy: ReviewPolicy = ReviewPolicy.STANDARD): Double {
        val days = max((at - (lastReviewed ?: since)) / 86_400, 0.0)
        val recall = 2.0.pow(-days / max(stability, 0.1))
        return min(stability / policy.matureStability, 1.0) * recall
    }

    /**
     * The memory after a revision: a clean one strengthens it (more so the longer it waited), a stumble weakens it.
     * [weight] is how much the evidence counts; a sheikh's tasmee' grows the memory more than self-revision. A
     * stumble is a stumble whoever heard it.
     */
    fun revised(stumbled: Boolean, at: Moment, policy: ReviewPolicy, weight: Double = 1.0): AyahMemory {
        val next = if (stumbled) {
            copy(stability = max(stability * policy.lapseFactor, policy.minStability), lapses = lapses + 1,
                lastLapseAt = maxOf(at, lastLapseAt ?: at))
        } else {
            // Revising again before it has had time to slip strengthens it less (the spacing effect). The first
            // revision of a declared ayah counts in full: it was memorized long before, when isn't known.
            val days = max((at - (lastReviewed ?: since)) / 86_400, 0.0)
            val spacing = if (lastReviewed == null) 1.0 else (days / max(stability, 0.1)).coerceIn(0.1, 1.0)
            copy(stability = min(stability * (1 + (policy.growth - 1) * spacing * weight), policy.maxStability))
        }
        // A tasmee' can arrive after a later revision; the last revision never moves backwards.
        return next.copy(lastReviewed = maxOf(at, lastReviewed ?: at))
    }
}

/**
 * The ayat the student has memorized, numbered 0 until 6236 in Quran order, kept on the device and backed up to
 * the student's account (see `CloudSync`).
 */
class MemorizationStore(
    /** The file the records live in, or null to keep them in memory only (previews and tests). */
    private val file: File?,
    private val scope: CoroutineScope? = null,
) {
    var ayahs: Map<Int, AyahMemory> by mutableStateOf(emptyMap())
        private set

    /** Called after every change, so the backup can follow. */
    var onChange: (() -> Unit)? = null

    private var pendingSave: Job? = null
    private var unsaved = false

    @Serializable
    private class FileContents(val version: Int = 2, val ayahs: List<Record>) {
        @Serializable
        class Record(val ayah: Int, val memory: AyahMemory)
    }

    init {
        val file = file
        if (file != null && file.exists()) {
            runCatching { ProgressJson.decodeFromString<FileContents>(file.readText()) }.getOrNull()?.let { contents ->
                val loaded = LinkedHashMap<Int, AyahMemory>()
                for (record in contents.ayahs) loaded.putIfAbsent(record.ayah, record.memory)
                ayahs = loaded
            }
        }
    }

    val count: Int get() = ayahs.size

    fun memory(ayah: Int): AyahMemory? = ayahs[ayah]

    fun isMemorized(ayah: Int): Boolean = ayah in ayahs

    /** How many ayat of a range are memorized. */
    fun memorizedCount(range: IntRange): Int {
        val ayahs = ayahs
        return range.count { it in ayahs }
    }

    /**
     * The share of the Quran memorized, counting every juz' equally (a juz' is a twentieth of the Mushaf's pages,
     * whatever its number of ayat) and a juz' memorized in part by the share of its ayat.
     */
    fun quranShare(store: MushafStore): Double = (1..30).sumOf { juz ->
        val range = store.juzAyahs[juz] ?: return@sumOf 0.0
        memorizedCount(range).toDouble() / range.count()
    } / 30

    /** The average strength of everything memorized, from 0 to 1; null when nothing is memorized. */
    fun averageStrength(at: Moment = Moment.now(), policy: ReviewPolicy = ReviewPolicy.STANDARD): Double? {
        val ayahs = ayahs
        if (ayahs.isEmpty()) return null
        return ayahs.values.sumOf { it.strength(at, policy) } / ayahs.size
    }

    /** How strong an ayah's memorization is now, or null if it isn't memorized. */
    fun strength(ayah: Int, at: Moment = Moment.now(), policy: ReviewPolicy = ReviewPolicy.STANDARD): Double? =
        ayahs[ayah]?.strength(at, policy)

    /**
     * Records a revision of memorized ayat: the stumbled ones weaken, the rest grow stronger (by [weight], see
     * [AyahMemory.revised]). Ayat that aren't memorized are left alone.
     */
    fun recordRevision(revised: Iterable<Int>, stumbled: Set<Int>, at: Moment, policy: ReviewPolicy, weight: Double = 1.0) {
        val next = ayahs.toMutableMap()
        var changed = false
        for (ayah in revised) {
            val memory = next[ayah] ?: continue
            next[ayah] = memory.revised(ayah in stumbled, at, policy, weight)
            changed = true
        }
        if (changed) {
            ayahs = next
            scheduleSave()
            saveNow()
        }
    }

    /**
     * A teacher heard these ayat in a tasmee': the memorized ones among them are marked verified, except the
     * stumbled ones, which lose the mark until a teacher hears them clean again.
     */
    fun verify(heard: Iterable<Int>, except: Set<Int> = emptySet()) {
        val next = ayahs.toMutableMap()
        var changed = false
        for (ayah in heard) {
            val verified = ayah !in except
            val memory = next[ayah] ?: continue
            if (memory.verified == verified) continue
            next[ayah] = memory.copy(verified = verified)
            changed = true
        }
        if (changed) {
            ayahs = next
            scheduleSave()
            saveNow()
        }
    }

    fun toggle(ayah: Int) = mark(listOf(ayah), memorized = !isMemorized(ayah))

    /** Replaces everything memorized: restoring from the account, or clearing the device on signing out. */
    fun replaceAll(memories: Map<Int, AyahMemory>) {
        if (memories == ayahs) return
        ayahs = memories.filterKeys { it in 0 until MushafStore.AYAH_COUNT }
        scheduleSave()
        saveNow()
    }

    /**
     * Marks ayat as newly memorized in Aqra (a portion of the plan): they start at the plan's short half-life, so
     * they're faint and come back soon. Ayat already memorized keep what's known about them.
     */
    fun learn(learned: Iterable<Int>, at: Moment = Moment.now(), stability: Double) {
        val next = ayahs.toMutableMap()
        var changed = false
        for (ayah in learned) {
            if (ayah !in 0 until MushafStore.AYAH_COUNT || ayah in next) continue
            next[ayah] = AyahMemory(stability = stability, since = at, learnedAt = at)
            changed = true
        }
        if (changed) {
            ayahs = next
            scheduleSave()
            saveNow()
        }
    }

    /** The memorized ayat that are mastered (see [AyahMemory.isMastered]), counted in a range. */
    fun masteredCount(range: IntRange, policy: StagePolicy = StagePolicy.STANDARD): Int {
        val ayahs = ayahs
        return range.count { ayahs[it]?.isMastered(policy) == true }
    }

    /** The memorized ayat a teacher verified, counted in a range. */
    fun verifiedCount(range: IntRange): Int {
        val ayahs = ayahs
        return range.count { ayahs[it]?.verified == true }
    }

    /** Marks ayat as memorized (keeping what's already known about them) or as not memorized. */
    fun mark(range: Iterable<Int>, memorized: Boolean) {
        val next = ayahs.toMutableMap()
        var changed = false
        val now = Moment.now()
        for (ayah in range) {
            if (ayah !in 0 until MushafStore.AYAH_COUNT || (ayah in next) == memorized) continue
            if (memorized) next[ayah] = AyahMemory(since = now) else next.remove(ayah)
            changed = true
        }
        if (changed) {
            ayahs = next
            scheduleSave()
        }
    }

    // MARK: - Saving

    /** Writes shortly after the last change, so marking many ayat at once writes once. */
    private fun scheduleSave() {
        onChange?.invoke()
        val file = file ?: return
        unsaved = true
        pendingSave?.cancel()
        val scope = scope ?: return
        val contents = contents()
        pendingSave = scope.launch {
            delay(300)
            write(contents, file)
            unsaved = false
        }
    }

    /** Writes any change still waiting to be saved, right away. */
    fun saveNow() {
        val file = file ?: return
        if (!unsaved) return
        pendingSave?.cancel()
        pendingSave = null
        write(contents(), file)
        unsaved = false
    }

    private fun contents() = FileContents(ayahs = ayahs.entries.sortedBy { it.key }.map { FileContents.Record(it.key, it.value) })

    private fun write(contents: FileContents, file: File) {
        writeAtomically(file, ProgressJson.encodeToString(FileContents.serializer(), contents))
    }
}

/** Writes a file through a temporary one, so a crash never leaves it half written. */
fun writeAtomically(file: File, text: String) {
    runCatching {
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(text)
        if (!temporary.renameTo(file)) {
            file.delete()
            temporary.renameTo(file)
        }
    }
}

/**
 * The Mushaf's marking mode. A tap marks or unmarks one ayah. Pressing and holding an ayah starts a range: the next
 * tap, on any page, marks every ayah from there to it (or unmarks them, when the first was marked).
 */
class MarkingSession(val memorization: MemorizationStore) {
    /** Where a range started, while it waits for its last ayah. */
    var rangeStart: Int? by mutableStateOf(null)
        private set
    private var rangeMarks = true

    fun tap(ayah: Int) {
        val start = rangeStart
        if (start != null) {
            memorization.mark(min(start, ayah)..max(start, ayah), memorized = rangeMarks)
            rangeStart = null
        } else {
            memorization.toggle(ayah)
        }
    }

    /** Starts a range at an ayah, marking it (or unmarking it, if it was marked) right away. */
    fun beginRange(ayah: Int) {
        rangeMarks = !memorization.isMemorized(ayah)
        memorization.mark(listOf(ayah), memorized = rangeMarks)
        rangeStart = ayah
    }

    fun cancelRange() {
        rangeStart = null
    }

    /** Marks every ayah of the given pages, or unmarks them when they're all already marked. */
    fun toggle(ayahs: IntRange) {
        memorization.mark(ayahs, memorized = memorization.memorizedCount(ayahs) < ayahs.count())
    }
}
