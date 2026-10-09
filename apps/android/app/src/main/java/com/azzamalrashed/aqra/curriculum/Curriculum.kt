package com.azzamalrashed.aqra.curriculum

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.ProgressJson
import com.azzamalrashed.aqra.core.newId
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.memorization.writeAtomically
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.tasmee.TasmeeRecord
import kotlinx.serialization.Serializable
import java.io.File
import kotlin.random.Random

/** The rules of the stages, in one place so they can be tuned after trying them (docs/SRS.md, §3.7). */
data class StagePolicy(
    /** An ayah is mastered once its half-life reaches this many days and its last revision was clean. */
    val masteryStability: Double = 60.0,
    /** The share of a stage's ayat that must be memorized to pass it. */
    val requiredMemorized: Double = 1.0,
    /** The share of a stage's ayat that must be mastered to pass it. */
    val requiredMastered: Double = 0.8,
    /** The in-app test: how many questions, and the share answered right to pass. */
    val testQuestions: Int = 10,
    val testPassScore: Double = 0.8,
    /** How long after a failed test it can be taken again, in seconds. */
    val retestCooldown: Double = 24 * 3_600.0,
    /** Whether passing a stage needs a sheikh's test. */
    val sheikhTestRequired: Boolean = true,
    /** A sheikh's test passes with at most this many mistakes per page heard; the teacher can change it per test. */
    val allowedMistakesPerPage: Int = 1,
) {
    companion object {
        val STANDARD = StagePolicy()
    }
}

/**
 * The curriculum's fixed structure (from the Etqan reference): ten stages of three juz' each. Stage k holds juz'
 * 3k−2…3k, and it's the k-th of the ten stairs drawn on the home.
 */
object Curriculum {
    const val STAGE_COUNT = 10
    const val JUZ_PER_STAGE = 3

    fun juz(stage: Int): IntRange {
        val s = stage.coerceIn(1, STAGE_COUNT)
        return (s - 1) * JUZ_PER_STAGE + 1..s * JUZ_PER_STAGE
    }

    fun stage(juz: Int): Int = (juz.coerceIn(1, 30) - 1) / JUZ_PER_STAGE + 1
}

/** How far a stage has come: its ayat memorized, mastered and verified. */
data class StageProgress(
    val stage: Int,
    val ayahs: IntRange,
    val memorized: Int,
    val mastered: Int,
    val verified: Int,
) {
    val total: Int get() = ayahs.count()
    val memorizedShare: Double get() = memorized.toDouble() / maxOf(total, 1)
    val masteredShare: Double get() = mastered.toDouble() / maxOf(total, 1)
    val verifiedShare: Double get() = verified.toDouble() / maxOf(total, 1)

    companion object {
        fun of(stage: Int, store: MushafStore, memorization: MemorizationStore, policy: StagePolicy = StagePolicy.STANDARD): StageProgress {
            val juz = Curriculum.juz(stage)
            val first = store.juzAyahs[juz.first]?.first ?: 0
            val last = store.juzAyahs[juz.last]?.last ?: first
            val ayahs = first..last
            return StageProgress(stage, ayahs, memorization.memorizedCount(ayahs), memorization.masteredCount(ayahs, policy),
                memorization.verifiedCount(ayahs))
        }
    }
}

/** What passing a stage asks, and how far each is met. */
data class StageStatus(
    val progress: StageProgress,
    val testPassed: Boolean,
    /** The best in-app test score, if the test was taken. */
    val bestScore: Double?,
    val sheikhPassed: Boolean,
    val passedAt: Moment?,
    /** When a failed test can be taken again; null when it can be taken now. */
    val retestAt: Moment?,
    val policy: StagePolicy,
) {
    enum class Requirement { MEMORIZED, MASTERED, TEST, SHEIKH }

    fun isMet(requirement: Requirement): Boolean = when (requirement) {
        Requirement.MEMORIZED -> progress.memorizedShare >= policy.requiredMemorized - 0.000_1
        Requirement.MASTERED -> progress.masteredShare >= policy.requiredMastered - 0.000_1
        Requirement.TEST -> testPassed
        Requirement.SHEIKH -> !policy.sheikhTestRequired || sheikhPassed
    }

    val requirements: List<Requirement> get() = Requirement.entries.filter { it != Requirement.SHEIKH || policy.sheikhTestRequired }
    val meetsAll: Boolean get() = Requirement.entries.all(::isMet)
    val isPassed: Boolean get() = passedAt != null

    /** The in-app test can be taken once the stage is memorized, and not again too soon after failing. */
    fun canTakeTest(at: Moment = Moment.now()): Boolean = isMet(Requirement.MEMORIZED) && (retestAt?.let { at >= it } ?: true)
}

/** A question of a stage's in-app test. Ayat are shown in the Complex's own text and font, as published. */
data class TestQuestion(
    val id: Int,
    val kind: Kind,
    /** The ayah asked about. */
    val ayah: Int,
    /** For [Kind.NEXT_AYAH], ayat; for [Kind.WHICH_SURAH], surah numbers. */
    val options: List<Int>,
    val answer: Int,
) {
    enum class Kind {
        /** Which ayah comes after this one? */
        NEXT_AYAH,
        /** Which surah is this ayah from? */
        WHICH_SURAH,
    }

    companion object {
        /**
         * A stage's test: questions on its memorized ayat, alternating kinds, each with four choices. Empty when the
         * stage has too little memorized to ask about.
         */
        fun test(stage: Int, count: Int, store: MushafStore, memorization: MemorizationStore, random: Random): List<TestQuestion> {
            val progress = StageProgress.of(stage, store, memorization)
            val memorized = progress.ayahs.filter(memorization::isMemorized)
            if (memorized.size < 4) return emptyList()
            // An ayah with its next one, both memorized and in the same surah.
            val followed = memorized.filter { ayah ->
                ayah + 1 <= progress.ayahs.last && memorization.isMemorized(ayah + 1) && store.surahOfAyah(ayah) == store.surahOfAyah(ayah + 1)
            }
            val surahs = memorized.map(store::surahOfAyah).toSortedSet().toList()
            val questions = ArrayList<TestQuestion>()
            val used = HashSet<Int>()
            for (index in 0 until count) {
                val wantsNext = index % 2 == 0 && followed.isNotEmpty()
                val next = if (wantsNext) followed.filter { it !in used }.randomOrNull(random) else null
                if (wantsNext && next != null) {
                    used += next
                    val others = memorized.filter { it != next && it != next + 1 }.shuffled(random).take(3)
                    if (others.size != 3) continue
                    questions += TestQuestion(index, Kind.NEXT_AYAH, next, (others + (next + 1)).shuffled(random), next + 1)
                } else {
                    val ayah = memorized.filter { it !in used }.randomOrNull(random) ?: continue
                    used += ayah
                    val surah = store.surahOfAyah(ayah)
                    // Other surahs of the stage first, then the surahs nearest it.
                    val pool = surahs.filter { it != surah }.shuffled(random).toMutableList()
                    var distance = 1
                    while (pool.size < 3 && distance < 114) {
                        for (candidate in listOf(surah - distance, surah + distance)) {
                            if (candidate in 1..114 && candidate !in pool) pool += candidate
                        }
                        distance += 1
                    }
                    questions += TestQuestion(index, Kind.WHICH_SURAH, ayah, (pool.take(3) + surah).shuffled(random), surah)
                }
            }
            return questions
        }
    }
}

/**
 * The record of the stages: in-app test results, the sheikh's stage tests heard, and the stages passed. Kept on the
 * device and backed up with the rest of the journey.
 */
class AssessmentStore(private val file: File?, val policy: StagePolicy = StagePolicy.STANDARD) {
    @Serializable
    data class TestResult(
        val id: String = newId(),
        val stage: Int,
        val date: Moment,
        val questions: Int,
        val correct: Int,
    ) {
        val score: Double get() = correct.toDouble() / maxOf(questions, 1)
    }

    /** A teacher's test of a stage, from a tasmee' record. */
    @Serializable
    data class SheikhTest(
        /** The tasmee' record's id. */
        val id: String,
        val stage: Int,
        val date: Moment,
        val teacherName: String,
        val passed: Boolean,
    )

    var results: List<TestResult> by mutableStateOf(emptyList())
        private set
    var sheikhTests: List<SheikhTest> by mutableStateOf(emptyList())
        private set
    /** Each stage passed, and when. */
    var passes: Map<Int, Moment> by mutableStateOf(emptyMap())
        private set
    var updatedAt: Moment by mutableStateOf(Moment.DISTANT_PAST)
        private set
    var onChange: (() -> Unit)? = null
    /** Called when a stage is passed, so it can be celebrated. */
    var onPass: ((Int) -> Unit)? = null

    init {
        val file = file
        if (file != null && file.exists()) {
            runCatching { ProgressJson.decodeFromString(Snapshot.serializer(), file.readText()) }.getOrNull()?.let { snapshot ->
                results = snapshot.results
                sheikhTests = snapshot.sheikhTests
                passes = snapshot.passes
                updatedAt = snapshot.updatedAt
            }
        }
    }

    fun status(stage: Int, store: MushafStore, memorization: MemorizationStore, now: Moment = Moment.now()): StageStatus {
        val stageResults = results.filter { it.stage == stage }
        val passedTest = stageResults.any { it.score >= policy.testPassScore - 0.000_1 }
        val lastFailed = stageResults.lastOrNull()?.takeIf { it.score < policy.testPassScore }?.date
        val retestAt = lastFailed?.let { it + policy.retestCooldown }?.takeIf { it > now }
        return StageStatus(
            progress = StageProgress.of(stage, store, memorization, policy),
            testPassed = passedTest,
            bestScore = stageResults.maxOfOrNull { it.score },
            sheikhPassed = sheikhTests.any { it.stage == stage && it.passed },
            passedAt = passes[stage],
            retestAt = if (passedTest) null else retestAt,
            policy = policy,
        )
    }

    fun record(result: TestResult) {
        results = results + result
        save()
    }

    /** Keeps a teacher's stage test from a tasmee' record, once. */
    fun record(record: TasmeeRecord) {
        val test = record.test ?: return
        val passed = record.passesTest ?: return
        if (sheikhTests.any { it.id == record.id }) return
        sheikhTests = sheikhTests + SheikhTest(record.id, test.stage, record.at, record.teacherName, passed)
        save()
    }

    /** Marks every stage whose requirements are all met as passed (once), and returns those just passed. */
    fun checkPasses(store: MushafStore, memorization: MemorizationStore, now: Moment = Moment.now()): List<Int> {
        val passed = (1..Curriculum.STAGE_COUNT).filter { stage ->
            passes[stage] == null && status(stage, store, memorization, now).meetsAll
        }
        if (passed.isNotEmpty()) {
            passes = passes + passed.associateWith { now }
            save()
            passed.forEach { onPass?.invoke(it) }
        }
        return passed
    }

    // MARK: - Backup

    @Serializable
    data class Snapshot(
        val results: List<TestResult> = emptyList(),
        val sheikhTests: List<SheikhTest> = emptyList(),
        val passes: Map<Int, Moment> = emptyMap(),
        val updatedAt: Moment = Moment.DISTANT_PAST,
    ) {
        companion object {
            val EMPTY = Snapshot()

            /** Both copies as one: every result and test of both, and each stage passed at its earliest. */
            fun merge(local: Snapshot, remote: Snapshot): Snapshot {
                val ids = HashSet<String>()
                val tests = HashSet<String>()
                val passes = HashMap(local.passes)
                for ((stage, date) in remote.passes) passes[stage] = passes[stage]?.let { minOf(it, date) } ?: date
                return Snapshot(
                    results = (local.results + remote.results).sortedBy { it.date }.filter { ids.add(it.id) },
                    sheikhTests = (local.sheikhTests + remote.sheikhTests).sortedBy { it.date }.filter { tests.add(it.id) },
                    passes = passes,
                    updatedAt = maxOf(local.updatedAt, remote.updatedAt),
                )
            }
        }
    }

    val snapshot: Snapshot get() = Snapshot(results, sheikhTests, passes, updatedAt)

    fun apply(snapshot: Snapshot) {
        if (snapshot == this.snapshot) return
        results = snapshot.results
        sheikhTests = snapshot.sheikhTests
        passes = snapshot.passes
        updatedAt = snapshot.updatedAt
        save(touching = false)
    }

    private fun save(touching: Boolean = true) {
        if (touching) updatedAt = Moment.now()
        onChange?.invoke()
        val file = file ?: return
        writeAtomically(file, ProgressJson.encodeToString(Snapshot.serializer(), snapshot))
    }

    companion object {
        /**
         * The stage the student is in, steady through the day: the one holding the plan's next portion (whether
         * today's is due, done or a rest day), else the one of the latest ayah memorized in Aqra (marking what was
         * already known doesn't move it), else the first stage not yet passed.
         */
        fun currentStage(nextAyah: Int?, memorization: MemorizationStore, store: MushafStore, passes: Map<Int, Moment>): Int {
            if (nextAyah != null) return Curriculum.stage(store.juzOfAyah(nextAyah))
            val latest = memorization.ayahs.mapNotNull { (ayah, memory) -> memory.learnedAt?.let { ayah to it } }
                .maxWithOrNull(compareBy({ it.second.sinceReference }, { it.first }))
            if (latest != null && memorization.count < MushafStore.AYAH_COUNT) return Curriculum.stage(store.juzOfAyah(latest.first))
            return (1..Curriculum.STAGE_COUNT).firstOrNull { passes[it] == null } ?: Curriculum.STAGE_COUNT
        }
    }
}
