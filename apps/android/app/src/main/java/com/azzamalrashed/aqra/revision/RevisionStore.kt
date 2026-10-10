package com.azzamalrashed.aqra.revision

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.core.CalendarDay
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.ProgressJson
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.memorization.writeAtomically
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.tasmee.MistakeType
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.File
import java.time.ZoneId
import kotlin.math.ceil

/**
 * Every rule of revision in one place, so they can be tuned after trying them, not buried in the code.
 * See docs/REVISION.md; the iOS app keeps the same values.
 */
data class ReviewPolicy(
    /** The half-life, in days, given to ayat the student declares they already know: «متوسط», the default. */
    val declaredStability: Double = 14.0,
    /** The half-life of a declared juz' the student calls «متين»: revised regularly, without stumbling. */
    val firmStability: Double = 30.0,
    /** The half-life of a declared juz' the student says «يحتاج مراجعة». */
    val weakStability: Double = 5.0,
    /** How much a clean revision multiplies the half-life, when it comes after the memory has had time to slip. */
    val growth: Double = 2.5,
    /** What a stumble multiplies the half-life by. */
    val lapseFactor: Double = 0.3,
    val minStability: Double = 1.0,
    val maxStability: Double = 365.0,
    /** The half-life at which a memorization counts as fully established (full color). */
    val matureStability: Double = 90.0,
    /** After a stumble, the page comes back after these many days, one after another, while it stays clean. */
    val followUpDays: List<Int> = listOf(1, 3, 7),
    /** How much more a clean revision counts when a sheikh heard it in a tasmee'. Provisional. */
    val sheikhWeight: Double = 1.5,
    /** A peer's tasmee' sits between self-revision and a sheikh's. Provisional. */
    val peerWeight: Double = 1.25,
    /**
     * سبقي, the near lane: this many of the pages most recently memorized in Aqra come back every day, beside the daily
     * amount, until newer pages take their place. Provisional, see docs/REVISION.md.
     */
    val nearLanePages: Int = 20,
) {
    /** How firm a declared juz' is, as the student says at setup. */
    enum class Firmness { FIRM, MIDDLING, WEAK }

    /** The starting half-life for ayat declared at a firmness. */
    fun stability(firmness: Firmness): Double = when (firmness) {
        Firmness.FIRM -> firmStability
        Firmness.MIDDLING -> declaredStability
        Firmness.WEAK -> weakStability
    }

    companion object {
        val STANDARD = ReviewPolicy()

        /** A daily amount that goes through everything memorized in about a month. */
        fun suggestedDailyPages(memorizedPages: Int): Int = ceil(memorizedPages / 30.0).toInt().coerceIn(2, 20)
    }

    /** The weight of a revision's evidence: self-revision counts once; a peer's more, and a sheikh's more still. */
    fun weight(source: RevisionRecord.Source): Double = when (source) {
        RevisionRecord.Source.APP, RevisionRecord.Source.OUTSIDE -> 1.0
        RevisionRecord.Source.PEER -> peerWeight
        RevisionRecord.Source.SHEIKH -> sheikhWeight
    }
}

/** One page revised: when, how, and which of its ayat the student stumbled on. */
// A record another app wrote with a source or stumbles left out still reads (see CloudBackup.decodeRevision).
@Serializable
data class RevisionRecord(val date: Moment, val page: Int, val source: Source = Source.APP, val stumbles: List<Int> = emptyList()) {
    /** Who heard the revision: the student alone, in the app or outside it, a peer, or a sheikh in a tasmee'. */
    @Serializable
    enum class Source {
        @SerialName("app") APP,
        @SerialName("outside") OUTSIDE,
        @SerialName("peer") PEER,
        @SerialName("sheikh") SHEIKH,
    }
}

/** A page in today's plan. */
@Serializable
data class PlanItem(val page: Int, val kind: Kind = Kind.ROTATION, val done: Boolean = false) {
    @Serializable
    enum class Kind {
        /** It was stumbled on recently and comes back to be made firm. */
        @SerialName("followUp") FOLLOW_UP,
        /** سبقي: memorized in Aqra lately, it comes back every day. */
        @SerialName("near") NEAR,
        /** Its turn has come in the rotation through everything memorized. */
        @SerialName("rotation") ROTATION,
    }
}

/** Today's plan. It's fixed once made, so it doesn't shift while the student works through it. */
@Serializable
data class DayPlan(val day: CalendarDay, val items: List<PlanItem>) {
    val doneCount: Int get() = items.count { it.done }
    val isComplete: Boolean get() = items.isNotEmpty() && items.all { it.done }
}

@Serializable
data class FollowUp(
    val due: CalendarDay,
    /** Which of the policy's follow-up intervals it's on. */
    val step: Int = 0,
)

/**
 * The revision plan and its record, kept on the device.
 *
 * Each day the plan takes, in order: pages due for follow-up after a stumble, then the next pages of the rotation
 * through everything memorized, in Mushaf order, up to the daily amount. The rotation only moves on when its pages
 * are revised, so missed days don't pile up: tomorrow starts where the student stopped.
 */
class RevisionStore(
    /** The file the record lives in, or null to keep it in memory only (previews and tests). */
    private val file: File?,
    val policy: ReviewPolicy = ReviewPolicy.STANDARD,
    /** The days are counted in this time zone; by default the device's, as it changes. */
    zone: ZoneId? = null,
) {
    private val fixedZone = zone
    private val zone: ZoneId get() = fixedZone ?: ZoneId.systemDefault()

    /** The pages to revise each day, or null until the student chooses (a suggestion is used meanwhile). */
    var dailyPages: Int? by mutableStateOf(null)
        private set
    /** The page the rotation continues from. */
    var rotationCursor: Int by mutableStateOf(1)
        private set
    var followUps: Map<Int, FollowUp> by mutableStateOf(emptyMap())
        private set
    var plan: DayPlan? by mutableStateOf(null)
        private set
    var history: List<RevisionRecord> by mutableStateOf(emptyList())
        private set
    /**
     * The days on which at least one page was revised, kept apart from the history so a long streak isn't cut short
     * when old records are dropped.
     */
    var revisedDays: Set<CalendarDay> by mutableStateOf(emptySet())
        private set
    /** The days on which the whole of that day's wird was revised. */
    var completedDays: Set<CalendarDay> by mutableStateOf(emptySet())
        private set
    /** When any of it last changed, to tell which copy is newer when merging with the account's. */
    var updatedAt: Moment by mutableStateOf(Moment.DISTANT_PAST)
        private set
    /** Whether the file on the device couldn't be read: it was set aside, and the account's copy must come first. */
    var loadFailed = false
        private set

    /** Called after every change, so the backup can follow. */
    var onChange: (() -> Unit)? = null
    /** Called after each page is recorded, so rewards can follow. */
    var onRecord: ((RevisionRecord) -> Unit)? = null

    @Serializable
    private class FileContents(
        /** 2: days are kept as their midnight in UTC (1 kept the device's; both read back as the same days). */
        val version: Int = 2,
        val dailyPages: Int? = null,
        val rotationCursor: Int,
        val followUps: List<FollowUpRecord>,
        val plan: DayPlan? = null,
        val history: List<RevisionRecord>,
        /** Missing from files written before the streak was kept; it's then rebuilt from the history. */
        val revisedDays: List<CalendarDay>? = null,
        val completedDays: List<CalendarDay>? = null,
        val updatedAt: Moment? = null,
    ) {
        @Serializable
        class FollowUpRecord(val page: Int, val due: CalendarDay, val step: Int)
    }

    init {
        val file = file
        if (file != null && file.exists()) {
            val contents = runCatching { ProgressJson.decodeFromString<FileContents>(file.readText()) }.getOrNull()
            if (contents == null) {
                // An unreadable file is kept aside, never replaced by an empty one; the account's copy comes first.
                MemorizationStore.setAside(file)
                loadFailed = true
            }
            contents?.let { contents ->
                dailyPages = contents.dailyPages
                rotationCursor = contents.rotationCursor
                followUps = contents.followUps.associate { it.page to FollowUp(it.due, it.step) }
                plan = contents.plan
                history = contents.history
                revisedDays = (contents.revisedDays ?: contents.history.map { CalendarDay.of(it.date, this.zone) }).toSet()
                completedDays = contents.completedDays.orEmpty().toSet()
                // Files from before backups were kept don't say when they changed; the file's own date does.
                updatedAt = contents.updatedAt ?: Moment.ofEpochMillis(file.lastModified())
            }
        }
    }

    // MARK: - Backup

    /** Everything the store keeps, as one value: what's backed up to the account and restored from it. */
    @Serializable
    data class Snapshot(
        val dailyPages: Int? = null,
        val rotationCursor: Int = 1,
        val followUps: Map<Int, FollowUp> = emptyMap(),
        val plan: DayPlan? = null,
        val history: List<RevisionRecord> = emptyList(),
        val revisedDays: List<CalendarDay> = emptyList(),
        /** Missing from backups made before it was kept. */
        val completedDays: List<CalendarDay>? = null,
        val updatedAt: Moment = Moment.DISTANT_PAST,
    ) {
        companion object {
            val EMPTY = Snapshot()
        }
    }

    val snapshot: Snapshot
        get() = Snapshot(dailyPages, rotationCursor, followUps, plan, history, revisedDays.sorted(),
            completedDays.sorted().ifEmpty { null }, updatedAt)

    /** Replaces everything with a snapshot: restoring from the account, or clearing the device on signing out. */
    fun apply(snapshot: Snapshot) {
        if (snapshot == this.snapshot) return
        dailyPages = snapshot.dailyPages?.coerceIn(1, 40)
        rotationCursor = snapshot.rotationCursor.coerceIn(1, MushafStore.PAGE_COUNT)
        followUps = snapshot.followUps
        plan = snapshot.plan
        history = snapshot.history.takeLast(1_000)
        revisedDays = snapshot.revisedDays.toSet()
        completedDays = snapshot.completedDays.orEmpty().toSet()
        // A restore keeps the record's own date, so two devices holding one merged copy don't keep writing it to
        // each other; the student's own changes still date it from now.
        updatedAt = snapshot.updatedAt
        save(touching = false)
    }

    /** The daily amount in effect: the student's choice, or the suggestion for what they've memorized. */
    fun effectiveDailyPages(memorizedPages: Int): Int =
        dailyPages ?: ReviewPolicy.suggestedDailyPages(memorizedPages)

    fun setDailyPages(pages: Int) {
        dailyPages = pages.coerceIn(1, 40)
        save()
    }

    /**
     * «أين وصلت في مراجعتك؟»: the rotation continues from this page. Today's plan is made again from it, unless some of it
     * is already revised.
     */
    fun setRotationStart(page: Int) {
        rotationCursor = page.coerceIn(1, MushafStore.PAGE_COUNT)
        if (plan?.doneCount == 0) plan = null
        save()
    }

    // MARK: - Today's plan

    /**
     * Makes today's plan if there isn't one for today yet (or if the one there was empty), and drops pages that are
     * no longer memorized from it. [nearPages] is the near lane (سبقي), from [nearLanePages].
     */
    fun refreshPlan(memorizedPages: List<Int>, now: Moment = Moment.now(), nearPages: List<Int> = emptyList()) {
        val day = today(now)
        val memorized = memorizedPages.toSet()
        val current = plan
        if (current != null && current.day == day && current.items.isNotEmpty()) {
            val kept = current.items.filter { it.done || it.page in memorized }
            if (kept != current.items) {
                plan = current.copy(items = kept)
                save()
            }
            return
        }

        val amount = effectiveDailyPages(memorizedPages.size)
        // Pages due for follow-up come first, the most overdue first, up to half the daily amount: the rotation always has
        // the other half, so it keeps moving through everything memorized.
        val due = followUps.entries
            .filter { it.value.due <= day && it.key in memorized }
            .sortedWith(compareBy({ it.value.due }, { it.key }))
            .take(maxOf(amount / 2, 1))
            .map { PlanItem(it.key, PlanItem.Kind.FOLLOW_UP) }
        val taken = due.map { it.page }.toMutableSet()

        // Then the near lane, in Mushaf order: what was memorized lately, every day, beside the daily amount.
        val near = nearPages.filter { it in memorized && it !in taken }.sorted().map { PlanItem(it, PlanItem.Kind.NEAR) }
        taken += near.map { it.page }

        // Then the rotation, from where it stopped, wrapping round to the start of what's memorized.
        val ordered = memorizedPages.sorted()
        val start = ordered.indexOfFirst { it >= rotationCursor }.let { if (it < 0) 0 else it }
        val wrapped = if (ordered.isEmpty()) emptyList() else ordered.subList(start, ordered.size) + ordered.subList(0, start)
        val rotation = wrapped
            .filter { it !in taken }
            .take(maxOf(amount - due.size, 1))
            .map { PlanItem(it, PlanItem.Kind.ROTATION) }

        plan = DayPlan(day, due + near + rotation)
        save()
    }

    /** سبقي: the pages most recently memorized in Aqra, before today, up to the policy's number, in Mushaf order. */
    fun nearLanePages(store: MushafStore, memorization: MemorizationStore, now: Moment = Moment.now()): List<Int> {
        if (policy.nearLanePages <= 0) return emptyList()
        val today = today(now)
        val ayahs = memorization.ayahs
        val learned = (1..MushafStore.PAGE_COUNT).mapNotNull { page ->
            val latest = store.page(page).ayahs.mapNotNull { ayahs[it]?.learnedAt }.maxOrNull()
            if (latest != null && CalendarDay.of(latest, zone) < today) page to latest else null
        }
        return learned.sortedWith(compareByDescending<Pair<Int, Moment>> { it.second }.thenByDescending { it.first })
            .take(policy.nearLanePages).map { it.first }.sorted()
    }

    /**
     * How many days the rotation takes to go through everything memorized outside the near lane, at today's pace: the
     * rotation pages of today's plan (the daily amount until there is one).
     */
    fun cycleDays(memorizedPages: Int, nearPages: Int = 0, now: Moment = Moment.now()): Int {
        val amount = effectiveDailyPages(memorizedPages)
        val current = plan
        val perDay = if (current != null && current.day == today(now)) current.items.count { it.kind == PlanItem.Kind.ROTATION } else amount
        val pool = maxOf(memorizedPages - nearPages, 0)
        return maxOf(ceil(pool.toDouble() / maxOf(perDay, 1)).toInt(), 1)
    }

    // MARK: - Recording

    /**
     * Records a revised page: updates its memorized ayat, its follow-up and the rotation, and checks it off today.
     * [ayahs] are the page's memorized ayat (the ones the revision covered), [stumbles] those the student stumbled
     * on, and [source] who heard it; a sheikh's tasmee' counts more (see [ReviewPolicy.weight]).
     */
    fun record(
        page: Int,
        ayahs: List<Int>,
        stumbles: Set<Int>,
        source: RevisionRecord.Source,
        memorization: MemorizationStore,
        now: Moment = Moment.now(),
    ) {
        memorization.recordRevision(ayahs, stumbles, now, policy, policy.weight(source))
        val day = today(now)

        // A stumble brings the page back tomorrow; a clean revision of a page due for follow-up spaces it out until it
        // leaves follow-up. Revising it again before it's due changes nothing: the step waits for its day.
        val nextFollowUps = followUps.toMutableMap()
        if (stumbles.isNotEmpty()) {
            nextFollowUps[page] = FollowUp(day + (policy.followUpDays.firstOrNull() ?: 1), 0)
        } else {
            followUps[page]?.takeIf { it.due <= day }?.let { followUp ->
                val next = followUp.step + 1
                if (next < policy.followUpDays.size) {
                    nextFollowUps[page] = FollowUp(day + policy.followUpDays[next], next)
                } else {
                    nextFollowUps.remove(page)
                }
            }
        }
        followUps = nextFollowUps

        // The page is checked off in the plan it belongs to, even one made the day before: a wird carried on past
        // midnight moves on rather than reopening the page.
        val current = plan
        val index = current?.items?.indexOfFirst { it.page == page } ?: -1
        if (current != null && index >= 0) {
            val items = current.items.toMutableList()
            items[index] = items[index].copy(done = true)
            val updated = current.copy(items = items)
            plan = updated
            if (updated.isComplete) completedDays = completedDays + updated.day
            // The rotation moves past the leading run of revised rotation pages, so a page skipped today (or revised
            // out of order) is still first tomorrow.
            var cursor = rotationCursor
            for (item in items.filter { it.kind == PlanItem.Kind.ROTATION }) {
                if (!item.done) break
                cursor = item.page % MushafStore.PAGE_COUNT + 1
            }
            rotationCursor = cursor
        }

        revisedDays = revisedDays + day
        val entry = RevisionRecord(now, page, source, stumbles.sorted())
        history = (history + entry).takeLast(1_000)
        save()
        onRecord?.invoke(entry)
    }

    /**
     * Brings pages back for follow-up from tomorrow, as after a stumble: a portion just memorized, or pages the student
     * chose to strengthen. A page already due sooner keeps its date.
     */
    fun followUp(pages: Iterable<Int>, now: Moment = Moment.now()) {
        val due = today(now) + (policy.followUpDays.firstOrNull() ?: 1)
        val next = followUps.toMutableMap()
        var changed = false
        for (page in pages.toSet()) {
            if (page !in 1..MushafStore.PAGE_COUNT) continue
            val existing = next[page]
            if (existing != null && existing.due <= due) continue
            next[page] = FollowUp(due, 0)
            changed = true
        }
        if (changed) {
            followUps = next
            save()
        }
    }

    // MARK: - Streak

    /**
     * The days in a row, up to today, on which the student revised. Today not being revised yet doesn't break it:
     * until the day ends, the streak counts back from yesterday.
     */
    fun streak(now: Moment = Moment.now()): Int {
        var day = today(now)
        if (day !in revisedDays) day += -1
        var count = 0
        while (day in revisedDays) {
            count += 1
            day += -1
        }
        return count
    }

    /** Whether the student revised on each of the last [count] days, oldest first, ending today. */
    fun recentDays(count: Int = 7, now: Moment = Moment.now()): List<Boolean> {
        val today = today(now)
        return (count - 1 downTo 0).map { today + -it in revisedDays }
    }

    /** The day it is now, in the device's time zone (or the one the store was made with). */
    fun today(now: Moment = Moment.now()): CalendarDay = CalendarDay.of(now, zone)

    // MARK: - Saving

    private fun save(touching: Boolean = true) {
        if (touching) updatedAt = Moment.now()
        onChange?.invoke()
        val file = file ?: return
        val contents = FileContents(
            dailyPages = dailyPages, rotationCursor = rotationCursor,
            followUps = followUps.entries.sortedBy { it.key }.map { FileContents.FollowUpRecord(it.key, it.value.due, it.value.step) },
            plan = plan, history = history, revisedDays = revisedDays.sorted(), completedDays = completedDays.sorted(),
            updatedAt = updatedAt,
        )
        writeAtomically(file, ProgressJson.encodeToString(FileContents.serializer(), contents))
    }

    companion object {
        /** The pages that hold any memorized ayah, in Mushaf order. */
        fun memorizedPages(store: MushafStore, memorization: MemorizationStore): List<Int> {
            val ayahs = memorization.ayahs
            return (1..MushafStore.PAGE_COUNT).filter { page -> store.page(page).ayahs.any { it in ayahs } }
        }
    }
}

/**
 * Revising one page: its memorized ayat are veiled and revealed one at a time, and the student marks the ones they
 * stumbled on.
 */
class RevisionSession(
    val page: Int,
    /** The page's memorized ayat, in order: the ones this revision covers. */
    val ayahs: List<Int>,
) {
    /** A word of the page: its ayah and its place in the ayah, from 1. */
    data class WordRef(val ayah: Int, val position: Int)

    /** How many of them are revealed, from the first. */
    var revealed: Int by mutableStateOf(0)
        private set
    /** When the recitation is followed word by word: how many words of the next ayah are revealed, by their place in it. */
    var revealedPosition: Int by mutableStateOf(0)
        private set
    var stumbles: Set<Int> by mutableStateOf(emptySet())
        private set
    /** What kind each stumble was, when the listener could tell. */
    var stumbleKinds: Map<Int, Set<MistakeType>> by mutableStateOf(emptyMap())
        private set
    /** Words shown after a long pause (the prompt, تلقين). */
    var prompts: Set<WordRef> by mutableStateOf(emptySet())
        private set
    /** Ayat whose stumble the student took back: the listener doesn't mark them again. */
    private var cleared: Set<Int> = emptySet()

    val isComplete: Boolean get() = revealed >= ayahs.size

    /**
     * The ayat «تم» records: those revealed (in full), or all of the page's when the student says they recited the rest
     * from memory too.
     */
    fun revisedAyahs(countingRest: Boolean): List<Int> = if (countingRest) ayahs else ayahs.take(minOf(revealed, ayahs.size))

    /** Whether an ayah is covered by this revision. */
    fun covers(ayah: Int): Boolean = ayah in ayahs

    /** Whether an ayah is still veiled, all of it or the rest of it. */
    fun isVeiled(ayah: Int): Boolean {
        val index = ayahs.indexOf(ayah)
        return index >= 0 && index >= revealed
    }

    /**
     * Whether a word of the page is still veiled. The ayah-end marker comes after the ayah's last word, so it's revealed
     * with the whole ayah.
     */
    fun isVeiled(ayah: Int, position: Int): Boolean {
        val index = ayahs.indexOf(ayah)
        if (index < 0) return false
        if (index == revealed) return position > revealedPosition
        return index > revealed
    }

    /** A tap on a revealed ayah marks or unmarks a stumble on it; any other tap reveals the next ayah. */
    fun tap(ayah: Int?) {
        if (ayah != null && covers(ayah) && !isVeiled(ayah)) {
            if (ayah in stumbles) clearStumble(ayah) else {
                stumbles = stumbles + ayah
                cleared = cleared - ayah
            }
        } else {
            revealNext()
        }
    }

    fun revealNext() {
        revealed = minOf(revealed + 1, ayahs.size)
        revealedPosition = 0
    }

    /** «تعثّرتُ هنا»: the student stumbled reciting the next ayah from memory. It's revealed, marked as a stumble. */
    fun stumbleOnNext() {
        if (isComplete) return
        val ayah = ayahs[revealed]
        revealNext()
        stumbles = stumbles + ayah
        cleared = cleared - ayah
    }

    fun revealAll() {
        revealed = ayahs.size
        revealedPosition = 0
    }

    /**
     * Reveals the page up to a word heard: the ayat before its ayah in full, and its ayah up to it — all of it when
     * [endsAyah] (its last word on this page).
     */
    fun reveal(through: WordRef, endsAyah: Boolean) {
        val index = ayahs.indexOf(through.ayah)
        if (index < 0) return
        if (endsAyah) {
            if (index + 1 <= revealed) return
            revealed = index + 1
            revealedPosition = 0
        } else if (index > revealed || (index == revealed && through.position > revealedPosition)) {
            revealed = index
            revealedPosition = through.position
        }
    }

    /** A word shown after a long pause. */
    fun prompt(word: WordRef) {
        if (word !in prompts) prompts = prompts + word
    }

    /** Marks an ayah as stumbled on, whatever it was (a listener classifying the stumble). */
    fun markStumble(ayah: Int) {
        if (covers(ayah)) stumbles = stumbles + ayah
    }

    /** Marks an ayah as stumbled on in the ways the listener heard. One the student cleared stays cleared. */
    fun markStumble(ayah: Int, kinds: Set<MistakeType>) {
        if (!covers(ayah) || ayah in cleared || stumbleKinds[ayah].orEmpty().containsAll(kinds)) return
        stumbles = stumbles + ayah
        stumbleKinds = stumbleKinds + (ayah to (stumbleKinds[ayah].orEmpty() + kinds))
    }

    fun clearStumble(ayah: Int) {
        stumbles = stumbles - ayah
        stumbleKinds = stumbleKinds - ayah
        cleared = cleared + ayah
    }
}
