package com.azzamalrashed.aqra.plan

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.ProgressJson
import com.azzamalrashed.aqra.core.newId
import com.azzamalrashed.aqra.core.weekday
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.memorization.writeAtomically
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.RevisionStore
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.File
import java.time.ZoneId
import kotlin.math.ceil
import kotlin.math.max

/** The rules of the personal plan, in one place so they can be tuned after trying them (docs/SRS.md, §3.7). */
data class PlanPolicy(
    /** The daily amounts offered, in lines of the 15-line page: ¼, ½, ¾, 1, 1¼ and 1½ pages. */
    val amountOptions: List<Int> = listOf(4, 8, 11, 15, 19, 23),
    val defaultAmount: Int = 8,
    /** Weekdays as the iOS app numbers them (1 is Sunday, 7 Saturday): every day but Friday. */
    val defaultStudyDays: Set<Int> = setOf(1, 2, 3, 4, 5, 7),
    /** The half-life a newly memorized ayah starts at: short, so it's faint and comes back soon. */
    val newStability: Double = 2.0,
    /** The recent pace is measured over this many days, once this many study days have passed in them. */
    val paceWindowDays: Int = 28,
    val minPaceDays: Int = 7,
) {
    companion object {
        val STANDARD = PlanPolicy()
    }
}

/** How the student memorizes new portions: how much a day, on which days, and in which order. */
@Serializable
data class MemorizationPlan(
    /** The daily amount, in lines of the page. */
    val dailyLines: Int,
    /** Weekdays (1 is Sunday). */
    val studyDays: Set<Int>,
    val order: Order,
    val paused: Boolean = false,
) {
    @Serializable
    enum class Order {
        /** From the end of the Mushaf: an-Nas, then the surahs before it, each from its first ayah (juz' ʿAmma first). */
        @SerialName("fromEnd") FROM_END,
        /** From the beginning: al-Fatiha, al-Baqarah, and on. */
        @SerialName("fromStart") FROM_START,
    }
}

/** One day's new memorization: what the plan proposed and what the student actually memorized, kept apart. */
@Serializable
data class Portion(
    val id: String = newId(),
    val date: Moment,
    val planned: List<Int>,
    val memorized: List<Int>,
    val plannedLines: Double,
    val actualLines: Double,
)

/** A change to the plan, kept so the plan's past isn't lost. */
@Serializable
data class PlanChange(
    val date: Moment,
    /** The plan from that date; null when it was turned off. */
    val plan: MemorizationPlan? = null,
)

/** What the plan asks of today. */
sealed interface TodayPortion {
    /** Today's portion, to memorize. */
    data class Due(val ayahs: List<Int>) : TodayPortion
    /** Memorized already today. */
    data class Done(val portion: Portion) : TodayPortion
    /** Not a study day; the next one. */
    data class RestDay(val next: Moment) : TodayPortion
    /** Everything is memorized. */
    data object Complete : TodayPortion
}

/**
 * The personal memorization plan: the daily new portion, its log (planned and actual), the plan's history, and the
 * expected completion date. Kept on the device and backed up with the rest of the journey.
 */
class PlanStore(
    private val file: File?,
    val policy: PlanPolicy = PlanPolicy.STANDARD,
    private val zone: ZoneId = ZoneId.systemDefault(),
) {
    var plan: MemorizationPlan? by mutableStateOf(null)
        private set
    var portions: List<Portion> by mutableStateOf(emptyList())
        private set
    var history: List<PlanChange> by mutableStateOf(emptyList())
        private set
    var updatedAt: Moment by mutableStateOf(Moment.DISTANT_PAST)
        private set
    /** Called after every change, so the backup can follow. */
    var onChange: (() -> Unit)? = null
    /** Called after a portion is memorized, so rewards can follow. */
    var onPortion: ((Portion) -> Unit)? = null

    init {
        val file = file
        if (file != null && file.exists()) {
            runCatching { ProgressJson.decodeFromString(Snapshot.serializer(), file.readText()) }.getOrNull()?.let { snapshot ->
                plan = snapshot.plan
                portions = snapshot.portions
                history = snapshot.history
                updatedAt = snapshot.updatedAt
            }
        }
    }

    // MARK: - The plan

    /** Sets (or changes) the plan, keeping the change in its history. */
    fun setPlan(plan: MemorizationPlan?, now: Moment = Moment.now()) {
        if (plan == this.plan) return
        val chosen = plan?.let {
            it.copy(dailyLines = it.dailyLines.coerceIn(1, 45), studyDays = it.studyDays.ifEmpty { policy.defaultStudyDays })
        }
        this.plan = chosen
        history = history + PlanChange(now, chosen)
        save()
    }

    fun isStudyDay(date: Moment): Boolean {
        val plan = plan ?: return false
        return date.weekday(zone) in plan.studyDays
    }

    // MARK: - Today

    /**
     * The first ayah of the plan's next portion, whatever today's state (due, done, a rest day, paused); null without
     * a plan or when everything is memorized.
     */
    fun nextAyah(memorization: MemorizationStore, store: MushafStore): Int? {
        val plan = plan ?: return null
        return nextPortion(plan.order, plan.dailyLines, store, memorization::isMemorized).firstOrNull()
    }

    fun today(memorization: MemorizationStore, store: MushafStore, now: Moment = Moment.now()): TodayPortion? {
        val plan = plan
        if (plan == null || plan.paused) return null
        val day = now.startOfDay(zone)
        portions.lastOrNull { it.date.startOfDay(zone) == day }?.let { return TodayPortion.Done(it) }
        if (memorization.count >= MushafStore.AYAH_COUNT) return TodayPortion.Complete
        if (!isStudyDay(now)) return TodayPortion.RestDay(nextStudyDay(day))
        val portion = nextPortion(plan.order, plan.dailyLines, store, memorization::isMemorized)
        return if (portion.isEmpty()) TodayPortion.Complete else TodayPortion.Due(portion)
    }

    private fun nextStudyDay(day: Moment): Moment {
        var next = day.plusDays(1, zone)
        repeat(7) { if (!isStudyDay(next)) next = next.plusDays(1, zone) }
        return next
    }

    // MARK: - «تم الحفظ»

    /**
     * Records today's portion: the ayat memorized (all of the proposal, or the first part of it) start their life in
     * the revision engine — faint, and back for follow-up tomorrow.
     */
    fun record(
        planned: List<Int>,
        memorized: List<Int>,
        store: MushafStore,
        memorization: MemorizationStore,
        revision: RevisionStore,
        now: Moment = Moment.now(),
    ): Portion? {
        // Kept in the order memorized (the plan's), not sorted: from the end, an-Nas comes before al-Falaq.
        val learned = memorized.filter { !memorization.isMemorized(it) }
        if (learned.isEmpty()) return null
        memorization.learn(learned, now, policy.newStability)
        val pages = HashSet<Int>()
        for (ayah in learned) {
            val page = store.pageOfAyah(ayah)
            pages += page
            // An ayah that runs onto the next page is on both.
            if (page < MushafStore.PAGE_COUNT && store.page(page + 1).ayahs.first == ayah) pages += page + 1
        }
        revision.followUp(pages, now)
        val portion = Portion(date = now, planned = planned, memorized = learned, plannedLines = store.lines(planned),
            actualLines = store.lines(learned))
        portions = portions + portion
        save()
        onPortion?.invoke(portion)
        return portion
    }

    // MARK: - The completion date

    /** Lines memorized per study day lately, once enough study days have passed to tell; null until then. */
    fun recentPace(now: Moment = Moment.now()): Double? {
        // Since the plan was last turned on: the earliest change in the run of changes that kept it on.
        var started: Moment? = null
        for (change in history.asReversed()) {
            if (change.plan == null) break
            started = change.date
        }
        val plan = plan ?: return null
        val start = started ?: return null
        val today = now.startOfDay(zone)
        val windowStart = maxOf(start.startOfDay(zone), today.plusDays(-policy.paceWindowDays.toLong(), zone))
        val doneToday = portions.any { it.date.startOfDay(zone) == today }
        var studyDays = 0
        var day = windowStart
        while (day < today || (day == today && doneToday)) {
            if (day.weekday(zone) in plan.studyDays) studyDays += 1
            day = day.plusDays(1, zone)
        }
        if (studyDays < policy.minPaceDays) return null
        val lines = portions.filter { it.date >= windowStart }.sumOf { it.actualLines }
        return lines / studyDays
    }

    /** When the whole Quran would be memorized at the recent pace (or the plan's, until there's a pace to go by). */
    fun completionDate(memorization: MemorizationStore, store: MushafStore, now: Moment = Moment.now()): Moment? {
        val plan = plan
        if (plan == null || plan.paused) return null
        val today = now.startOfDay(zone)
        val doneToday = portions.any { it.date.startOfDay(zone) == today }
        return estimate(plan, remainingLines(memorization, store), recentPace(now),
            if (doneToday) today.plusDays(1, zone) else today, zone)
    }

    /** Lines memorized in the last days, for the progress screen. */
    fun lines(inLast: Int, now: Moment = Moment.now()): Double {
        val start = now.startOfDay(zone).plusDays(-(inLast - 1).toLong(), zone)
        return portions.filter { it.date >= start }.sumOf { it.actualLines }
    }

    // MARK: - Backup

    @Serializable
    data class Snapshot(
        val plan: MemorizationPlan? = null,
        val portions: List<Portion> = emptyList(),
        val history: List<PlanChange> = emptyList(),
        val updatedAt: Moment = Moment.DISTANT_PAST,
    ) {
        companion object {
            val EMPTY = Snapshot()

            /** Both copies as one: the plan most recently changed, and the portions and history of both. */
            fun merge(local: Snapshot, remote: Snapshot): Snapshot {
                val newer = if (remote.updatedAt >= local.updatedAt) remote else local
                val ids = HashSet<String>()
                val changes = HashSet<PlanChange>()
                return newer.copy(
                    portions = (local.portions + remote.portions).sortedBy { it.date }.filter { ids.add(it.id) },
                    history = (local.history + remote.history).sortedBy { it.date }.filter { changes.add(it) },
                    updatedAt = maxOf(local.updatedAt, remote.updatedAt),
                )
            }
        }
    }

    val snapshot: Snapshot get() = Snapshot(plan, portions, history, updatedAt)

    fun apply(snapshot: Snapshot) {
        if (snapshot == this.snapshot) return
        plan = snapshot.plan
        portions = snapshot.portions
        history = snapshot.history
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
         * The order that continues what the student already knows: from the beginning when their memorization runs
         * from al-Baqarah, otherwise from the end (where most begin).
         */
        fun suggestedOrder(memorization: MemorizationStore, store: MushafStore): MemorizationPlan.Order {
            val first = store.juzAyahs[1]?.let(memorization::memorizedCount) ?: 0
            val last = store.juzAyahs[30]?.let(memorization::memorizedCount) ?: 0
            return if (first > last) MemorizationPlan.Order.FROM_START else MemorizationPlan.Order.FROM_END
        }

        /**
         * The next portion in the plan's order: the next ayat not yet memorized, about the daily amount, ending at an
         * ayah's end. It moves on to the next surah in the order only once the current one is finished.
         */
        fun nextPortion(order: MemorizationPlan.Order, dailyLines: Int, store: MushafStore, isMemorized: (Int) -> Boolean): List<Int> {
            val surahs = if (order == MemorizationPlan.Order.FROM_START) (1..114).toList() else (114 downTo 1).toList()
            val target = max(dailyLines, 1).toDouble()
            val portion = ArrayList<Int>()
            var lines = 0.0
            for (surah in surahs) {
                val range = store.surahAyahs[surah] ?: continue
                val first = range.firstOrNull { !isMemorized(it) } ?: continue
                var ayah = first
                while (ayah <= range.last && !isMemorized(ayah)) {
                    val length = store.ayahLines[ayah]
                    // A long ayah that would run far past the amount waits for tomorrow, once there's enough for today.
                    if (portion.isNotEmpty() && lines >= target * 0.5 && lines + length > target * 1.5) return portion
                    portion += ayah
                    lines += length
                    if (lines >= target - 0.05) {
                        // A surah with only a little left is finished today rather than left for tomorrow.
                        var rest = ayah + 1
                        var restLines = 0.0
                        while (rest <= range.last && !isMemorized(rest)) {
                            restLines += store.ayahLines[rest]
                            rest += 1
                        }
                        if (rest > range.last && restLines > 0 && restLines <= target * 0.25) portion += (ayah + 1)..range.last
                        return portion
                    }
                    ayah += 1
                }
                // An ayah already memorized inside the surah ends the portion; a finished surah leads to the next.
                if (ayah <= range.last && portion.isNotEmpty()) return portion
            }
            return portion
        }

        /** The lines not yet memorized. */
        fun remainingLines(memorization: MemorizationStore, store: MushafStore): Double {
            val ayahs = memorization.ayahs
            var total = 0.0
            for (ayah in 0 until MushafStore.AYAH_COUNT) if (ayah !in ayahs) total += store.ayahLines[ayah]
            return total
        }

        /** The study day on which the remaining lines would be done, at a pace (lines per study day) or the plan's own. */
        fun estimate(plan: MemorizationPlan, remainingLines: Double, pace: Double?, from: Moment, zone: ZoneId = ZoneId.systemDefault()): Moment? {
            if (remainingLines <= 0 || plan.studyDays.isEmpty()) return null
            val perDay = max(pace ?: plan.dailyLines.toDouble(), 0.5)
            var needed = ceil(remainingLines / perDay).toInt()
            var day = from.startOfDay(zone)
            // Fifty years at most: past that the date says nothing useful.
            repeat(18_300) {
                if (day.weekday(zone) in plan.studyDays) {
                    needed -= 1
                    if (needed <= 0) return day
                }
                day = day.plusDays(1, zone)
            }
            return null
        }
    }
}
