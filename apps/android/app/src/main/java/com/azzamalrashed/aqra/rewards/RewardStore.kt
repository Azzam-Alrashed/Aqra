package com.azzamalrashed.aqra.rewards

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.ProgressJson
import com.azzamalrashed.aqra.core.newId
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.memorization.writeAtomically
import com.azzamalrashed.aqra.plan.PlanStore
import com.azzamalrashed.aqra.plan.Portion
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.RevisionRecord
import com.azzamalrashed.aqra.revision.RevisionStore
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.time.ZoneId
import kotlin.math.roundToInt

/**
 * What each step of the journey earns, in one place so it can be tuned (docs/SRS.md, §3.7). Points are private:
 * they're the student's own encouragement, never a public rank.
 */
data class RewardPolicy(
    val pageRevisedInApp: Int = 2,
    val pageRevisedOutside: Int = 1,
    val pageHeardByPeer: Int = 3,
    val pageHeardBySheikh: Int = 5,
    /** Per page's worth of new memorization (15 lines), at least [minPortionPoints]. */
    val portionPerPage: Int = 5,
    val minPortionPoints: Int = 2,
    val wirdCompleted: Int = 5,
    val streakBonuses: Map<Int, Int> = mapOf(7 to 20, 30 to 50, 100 to 100),
    val stagePassed: Int = 100,
    val challengeCompleted: Int = 20,
) {
    companion object {
        val STANDARD = RewardPolicy()
    }
}

/** Milestones of the journey, each earned once. Their names are the iOS app's, as kept in the backup. */
enum class Achievement(val raw: String, val icon: String) {
    FIRST_REVISION("firstRevision", "🌱"),
    FIRST_WIRD("firstWird", "✅"),
    FIRST_PORTION("firstPortion", "✍️"),
    FIRST_JUZ("firstJuz", "📗"),
    FIRST_VERIFIED("firstVerified", "🎓"),
    FIRST_PEER("firstPeer", "🤝"),
    STREAK_7("streak7", "🔥"),
    STREAK_30("streak30", "🌙"),
    STREAK_100("streak100", "💎"),
    FIRST_STAGE("firstStage", "🪜"),
    FIVE_STAGES("fiveStages", "⛰️"),
    WHOLE_QURAN("wholeQuran", "⭐️"),
}

/** A goal the student sets themselves, for a week. */
@Serializable
data class Challenge(
    val id: String = newId(),
    val kind: Kind,
    val target: Int,
    val start: Moment,
    val end: Moment,
    val completedAt: Moment? = null,
) {
    @Serializable
    enum class Kind(val icon: String) {
        /** Complete the whole wird on this many days. */
        @SerialName("wirdDays") WIRD_DAYS("✅"),
        /** Revise this many pages. */
        @SerialName("pagesRevised") PAGES_REVISED("📄"),
        /** Memorize this many lines of new portions. */
        @SerialName("linesMemorized") LINES_MEMORIZED("✍️"),
        /** Revise every day. */
        @SerialName("dailyRevision") DAILY_REVISION("🔥"),
    }

    companion object {
        /** The goals offered for a week. */
        val OPTIONS = listOf(
            Kind.WIRD_DAYS to 5, Kind.WIRD_DAYS to 7, Kind.PAGES_REVISED to 30, Kind.PAGES_REVISED to 100,
            Kind.LINES_MEMORIZED to 30, Kind.LINES_MEMORIZED to 60, Kind.DAILY_REVISION to 7,
        )
    }
}

/** A moment to celebrate: points earned, an achievement, a stage passed, a challenge met. */
data class Celebration(val kind: Kind, val id: String = newId()) {
    sealed interface Kind {
        data class Points(val points: Int) : Kind
        data class Earned(val achievement: Achievement) : Kind
        data class Stage(val stage: Int) : Kind
        data class ChallengeMet(val kind: Challenge.Kind, val target: Int) : Kind
    }

    val isBig: Boolean get() = kind !is Kind.Points
}

/**
 * Points, achievements and personal challenges: small, frequent rewards, private to the student. Kept on the device
 * and backed up with the rest of the journey.
 */
class RewardStore(
    private val file: File?,
    val policy: RewardPolicy = RewardPolicy.STANDARD,
    private val zone: ZoneId = ZoneId.systemDefault(),
) {
    @Serializable
    data class Event(val date: Moment, val points: Int, val reason: String)

    var points: Int by mutableStateOf(0)
        private set
    /** The latest points earned, newest last. */
    var events: List<Event> by mutableStateOf(emptyList())
        private set
    /** When each achievement was earned, by its name (one a newer app knows is kept as it came). */
    var achievements: Map<String, Moment> by mutableStateOf(emptyMap())
        private set
    var challenges: List<Challenge> by mutableStateOf(emptyList())
        private set
    var updatedAt: Moment by mutableStateOf(Moment.DISTANT_PAST)
        private set
    /** What's being celebrated now, shown over the app for a moment. */
    var celebration: Celebration? by mutableStateOf(null)
        private set
    var onChange: (() -> Unit)? = null
    private val celebrationQueue = ArrayDeque<Celebration>()

    init {
        val file = file
        if (file != null && file.exists()) {
            runCatching { ProgressJson.decodeFromString(Snapshot.serializer(), file.readText()) }.getOrNull()?.let { snapshot ->
                points = snapshot.points
                events = snapshot.events
                achievements = snapshot.achievements
                challenges = snapshot.challenges
                updatedAt = snapshot.updatedAt
            }
        }
    }

    fun earnedAt(achievement: Achievement): Moment? = achievements[achievement.raw]

    // MARK: - Earning

    /** A page revised: points by who heard it, achievements, the wird completed, the streak's milestones. */
    fun revised(record: RevisionRecord, revision: RevisionStore, now: Moment = Moment.now()) {
        val earned = when (record.source) {
            RevisionRecord.Source.APP -> policy.pageRevisedInApp
            RevisionRecord.Source.OUTSIDE -> policy.pageRevisedOutside
            RevisionRecord.Source.PEER -> policy.pageHeardByPeer
            RevisionRecord.Source.SHEIKH -> if (record.stumbles.isEmpty()) policy.pageHeardBySheikh else policy.pageRevisedInApp
        }
        var total = earned
        var reason = "page"
        earn(Achievement.FIRST_REVISION, now)
        if (record.source == RevisionRecord.Source.PEER) earn(Achievement.FIRST_PEER, now)
        if (record.source == RevisionRecord.Source.SHEIKH && record.stumbles.isEmpty()) earn(Achievement.FIRST_VERIFIED, now)
        val day = now.startOfDay(zone)
        if (day in revision.completedDays && events.none { it.reason == "wird" && it.date.startOfDay(zone) == day }) {
            total += policy.wirdCompleted
            reason = "wird"
            earn(Achievement.FIRST_WIRD, now)
        }
        val streak = revision.streak(now)
        for ((days, bonus) in policy.streakBonuses) {
            if (streak < days) continue
            val achievement = if (days >= 100) Achievement.STREAK_100 else if (days >= 30) Achievement.STREAK_30 else Achievement.STREAK_7
            if (earnedAt(achievement) == null) {
                total += bonus
                earn(achievement, now)
            }
        }
        add(total, reason, now)
    }

    /** A new portion memorized. */
    fun memorized(portion: Portion, memorization: MemorizationStore, store: MushafStore, now: Moment = Moment.now()) {
        val earned = maxOf((portion.actualLines / 15 * policy.portionPerPage).roundToInt(), policy.minPortionPoints)
        earn(Achievement.FIRST_PORTION, now)
        noteMemorization(memorization, store, now)
        add(earned, "portion", now)
    }

    /** Milestones of what's memorized: a whole juz', the whole Quran. */
    fun noteMemorization(memorization: MemorizationStore, store: MushafStore, now: Moment = Moment.now()) {
        if ((1..30).any { juz -> store.juzAyahs[juz]?.let { memorization.memorizedCount(it) == it.count() } == true }) {
            earn(Achievement.FIRST_JUZ, now)
        }
        if (memorization.count == MushafStore.AYAH_COUNT) earn(Achievement.WHOLE_QURAN, now)
    }

    fun passedStage(stage: Int, totalPassed: Int, now: Moment = Moment.now()) {
        earn(Achievement.FIRST_STAGE, now)
        if (totalPassed >= 5) earn(Achievement.FIVE_STAGES, now)
        celebrate(Celebration(Celebration.Kind.Stage(stage)))
        add(policy.stagePassed, "stage", now, celebrating = false)
    }

    private fun earn(achievement: Achievement, date: Moment) {
        if (earnedAt(achievement) != null) return
        achievements = achievements + (achievement.raw to date)
        celebrate(Celebration(Celebration.Kind.Earned(achievement)))
        save()
    }

    private fun add(earned: Int, reason: String, date: Moment, celebrating: Boolean = true) {
        if (earned <= 0) return
        points += earned
        events = (events + Event(date, earned, reason)).takeLast(500)
        if (celebrating) celebrate(Celebration(Celebration.Kind.Points(earned)))
        save()
    }

    /** Points earned since a date. */
    fun points(since: Moment): Int = events.filter { it.date >= since }.sumOf { it.points }

    // MARK: - Celebrating

    private fun celebrate(next: Celebration) {
        // A big moment replaces the points it came with; several big ones take turns.
        val current = celebration
        if (current == null || (!current.isBig && next.isBig)) {
            celebration = next
        } else if (next.isBig) {
            celebrationQueue.addLast(next)
        }
    }

    /** The celebration on screen is done; the next one waiting, if any, takes its place. */
    fun finishCelebration() {
        celebration = celebrationQueue.removeFirstOrNull()
    }

    // MARK: - Challenges

    /** A challenge set for the coming week, from today. */
    fun start(kind: Challenge.Kind, target: Int, now: Moment = Moment.now()) {
        val start = now.startOfDay(zone)
        challenges = challenges + Challenge(kind = kind, target = target, start = start, end = start.plusDays(7, zone))
        save()
    }

    fun remove(challenge: Challenge) {
        challenges = challenges.filter { it.id != challenge.id }
        save()
    }

    /** The challenges still running, and those finished in the last week. */
    fun activeChallenges(now: Moment = Moment.now()): List<Challenge> =
        challenges.filter { it.end > now || (it.completedAt?.let { done -> now - done < 7 * 86_400.0 } ?: false) }

    /** How far a challenge has come, from what the student did in its week. */
    fun progress(challenge: Challenge, revision: RevisionStore, plan: PlanStore): Int {
        fun inWeek(date: Moment) = date >= challenge.start && date < challenge.end
        return when (challenge.kind) {
            Challenge.Kind.WIRD_DAYS -> revision.completedDays.count(::inWeek)
            Challenge.Kind.PAGES_REVISED -> revision.history.count { inWeek(it.date) }
            Challenge.Kind.LINES_MEMORIZED -> plan.portions.filter { inWeek(it.date) }.sumOf { it.actualLines }.toInt()
            Challenge.Kind.DAILY_REVISION -> revision.revisedDays.count(::inWeek)
        }
    }

    /** Marks challenges just met, and celebrates them. */
    fun checkChallenges(revision: RevisionStore, plan: PlanStore, now: Moment = Moment.now()) {
        var changed = false
        val next = challenges.map { challenge ->
            if (challenge.completedAt != null || challenge.end <= now || progress(challenge, revision, plan) < challenge.target) {
                challenge
            } else {
                celebrate(Celebration(Celebration.Kind.ChallengeMet(challenge.kind, challenge.target)))
                points += policy.challengeCompleted
                events = events + Event(now, policy.challengeCompleted, "challenge")
                changed = true
                challenge.copy(completedAt = now)
            }
        }
        if (changed) {
            challenges = next
            save()
        }
    }

    // MARK: - Backup

    @Serializable
    data class Snapshot(
        val points: Int = 0,
        val events: List<Event> = emptyList(),
        @Serializable(with = AchievementsSerializer::class)
        val achievements: Map<String, Moment> = emptyMap(),
        val challenges: List<Challenge> = emptyList(),
        val updatedAt: Moment = Moment.DISTANT_PAST,
    ) {
        companion object {
            val EMPTY = Snapshot()

            /**
             * Both copies as one: the larger total (points only grow), every achievement at its earliest, and the
             * challenges of both.
             */
            fun merge(local: Snapshot, remote: Snapshot): Snapshot {
                val seenEvents = HashSet<Event>()
                val ids = HashSet<String>()
                val achievements = HashMap(local.achievements)
                for ((name, date) in remote.achievements) achievements[name] = achievements[name]?.let { minOf(it, date) } ?: date
                val challenges = if (remote.updatedAt >= local.updatedAt) remote.challenges + local.challenges else local.challenges + remote.challenges
                return Snapshot(
                    points = maxOf(local.points, remote.points),
                    events = (local.events + remote.events).sortedBy { it.date }.filter { seenEvents.add(it) }.takeLast(500),
                    achievements = achievements,
                    challenges = challenges.filter { ids.add(it.id) }.sortedBy { it.start },
                    updatedAt = maxOf(local.updatedAt, remote.updatedAt),
                )
            }
        }
    }

    val snapshot: Snapshot get() = Snapshot(points, events, achievements, challenges, updatedAt)

    fun apply(snapshot: Snapshot) {
        if (snapshot == this.snapshot) return
        points = snapshot.points
        events = snapshot.events
        achievements = snapshot.achievements
        challenges = snapshot.challenges
        updatedAt = snapshot.updatedAt
        save(touching = false)
    }

    private fun save(touching: Boolean = true) {
        if (touching) updatedAt = Moment.now()
        onChange?.invoke()
        val file = file ?: return
        writeAtomically(file, ProgressJson.encodeToString(Snapshot.serializer(), snapshot))
    }
}

/**
 * The achievements as the iOS app writes them: a dictionary keyed by an enum is encoded by Swift as one flat array
 * of keys and values, `["firstRevision", 813013200, "firstWird", 813099600]`.
 */
object AchievementsSerializer : KSerializer<Map<String, Moment>> {
    private val list = ListSerializer(JsonElement.serializer())
    override val descriptor: SerialDescriptor = list.descriptor

    override fun serialize(encoder: Encoder, value: Map<String, Moment>) {
        val json = encoder as JsonEncoder
        val elements = value.entries.sortedBy { it.value }.flatMap { listOf(JsonPrimitive(it.key), JsonPrimitive(it.value.sinceReference)) }
        json.encodeJsonElement(JsonArray(elements))
    }

    override fun deserialize(decoder: Decoder): Map<String, Moment> {
        val elements = (decoder as JsonDecoder).decodeJsonElement() as? JsonArray ?: return emptyMap()
        val result = LinkedHashMap<String, Moment>()
        for (index in 0 until elements.size / 2) {
            val name = elements[index * 2].jsonPrimitive.contentOrNull ?: continue
            val date = elements[index * 2 + 1].jsonPrimitive.doubleOrNull ?: continue
            result[name] = Moment(date)
        }
        return result
    }
}
