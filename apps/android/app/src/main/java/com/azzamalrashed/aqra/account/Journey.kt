package com.azzamalrashed.aqra.account

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.ProgressJson
import com.azzamalrashed.aqra.core.decodeLossy
import com.azzamalrashed.aqra.curriculum.AssessmentStore
import com.azzamalrashed.aqra.memorization.writeAtomically
import com.azzamalrashed.aqra.quran.MushafStore
import java.io.File
import com.azzamalrashed.aqra.plan.PlanStore
import com.azzamalrashed.aqra.rewards.RewardStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

/**
 * The rest of the student's journey beside what's memorized and the revision record: the personal plan, the rewards
 * and the stages' assessments. Backed up together as one document, `users/{uid}/journey/state`.
 */
class Journey(
    val plan: PlanStore,
    val rewards: RewardStore,
    val assessments: AssessmentStore,
    val reading: ReadingStore = ReadingStore(file = null),
) {
    /** Called after any of them changes, so the backup can follow. */
    var onChange: (() -> Unit)? = null
        set(value) {
            field = value
            plan.onChange = value
            rewards.onChange = value
            assessments.onChange = value
            reading.onChange = value
        }

    @Serializable
    data class Snapshot(
        val plan: PlanStore.Snapshot = PlanStore.Snapshot.EMPTY,
        val rewards: RewardStore.Snapshot = RewardStore.Snapshot.EMPTY,
        val assessments: AssessmentStore.Snapshot = AssessmentStore.Snapshot.EMPTY,
        /** Missing from backups made before the ribbon existed. */
        val reading: ReadingStore.Snapshot? = null,
    ) {
        companion object {
            val EMPTY = Snapshot()

            fun merge(local: Snapshot, remote: Snapshot) = Snapshot(
                PlanStore.Snapshot.merge(local.plan, remote.plan),
                RewardStore.Snapshot.merge(local.rewards, remote.rewards),
                AssessmentStore.Snapshot.merge(local.assessments, remote.assessments),
                ReadingStore.Snapshot.merge(local.reading ?: ReadingStore.Snapshot.EMPTY, remote.reading ?: ReadingStore.Snapshot.EMPTY)
                    .takeIf { it != ReadingStore.Snapshot.EMPTY },
            )
        }
    }

    val snapshot: Snapshot get() = Snapshot(plan.snapshot, rewards.snapshot, assessments.snapshot,
        reading.snapshot.takeIf { it != ReadingStore.Snapshot.EMPTY })

    fun apply(snapshot: Snapshot) {
        plan.apply(snapshot.plan)
        rewards.apply(snapshot.rewards)
        assessments.apply(snapshot.assessments)
        reading.apply(snapshot.reading ?: ReadingStore.Snapshot.EMPTY)
    }

    companion object {
        /**
         * The journey as JSON. [carrying] is the account's copy as it was read: what a newer app wrote into it that
         * this one doesn't know — at the top, or within the plan, the rewards or the assessments — is written back as
         * it came.
         */
        fun encode(snapshot: Snapshot, carrying: JsonObject = JsonObject(emptyMap())): String {
            val known = ProgressJson.encodeToJsonElement(Snapshot.serializer(), snapshot).jsonObject
            val merged = LinkedHashMap<String, kotlinx.serialization.json.JsonElement>()
            for ((key, value) in carrying) if (key !in known) merged[key] = value
            for ((key, value) in known) {
                val old = carrying[key] as? JsonObject
                merged[key] = if (old != null && value is JsonObject) JsonObject(old.filterKeys { it !in value } + value) else value
            }
            return JsonObject(merged).toString()
        }

        /**
         * The account's journey as this app or the iOS app wrote it, or a newer version of either: a key missing or
         * unknown never fails it, and an entry of its lists that can't be read is skipped rather than losing the rest.
         */
        fun decode(json: String): Snapshot? {
            ProgressJson.decodeLossy(Snapshot.serializer(), json, LISTS)?.let { return it }
            // An unreadable ribbon is left out rather than losing the rest of the journey.
            val root = runCatching { ProgressJson.parseToJsonElement(json).jsonObject }.getOrNull() ?: return null
            if ("reading" !in root) return null
            return ProgressJson.decodeLossy(Snapshot.serializer(), JsonObject(root - "reading").toString(), LISTS)
        }

        private val LISTS =
            listOf("plan.portions", "plan.history", "rewards.events", "rewards.challenges", "assessments.results", "assessments.sheikhTests")

        /** The account's copy as a JSON object, to carry what this app doesn't know; empty if it isn't one. */
        fun original(json: String): JsonObject =
            runCatching { ProgressJson.parseToJsonElement(json).jsonObject }.getOrNull() ?: JsonObject(emptyMap())
    }
}

/**
 * Where the reader stopped: a ribbon (فاصل) they place in the Mushaf, which browsing, revising and marking never move.
 * Kept on the device and backed up with the rest of the journey, in the iOS app's layout.
 */
class ReadingStore(private val file: File?) {
    @Serializable
    data class Bookmark(val page: Int, val placedAt: Moment)

    @Serializable
    data class Snapshot(
        val bookmark: Bookmark? = null,
        /** When the ribbon was last placed or taken away, so a removal on one device isn't undone by another's copy. */
        val updatedAt: Moment = Moment.DISTANT_PAST,
    ) {
        companion object {
            val EMPTY = Snapshot()

            /** The more recent choice wins: a ribbon placed later, or a later removal. */
            fun merge(local: Snapshot, remote: Snapshot): Snapshot = if (remote.updatedAt > local.updatedAt) remote else local
        }
    }

    var bookmark: Bookmark? by mutableStateOf(null)
        private set
    var onChange: (() -> Unit)? = null
    private var updatedAt = Moment.DISTANT_PAST

    init {
        val file = file
        if (file != null && file.exists()) {
            runCatching { ProgressJson.decodeFromString(Snapshot.serializer(), file.readText()) }.getOrNull()?.let {
                bookmark = it.bookmark
                updatedAt = it.updatedAt
            }
        }
    }

    /** Places the ribbon on a page, or moves it there. */
    fun place(page: Int, at: Moment = Moment.now()) {
        if (page !in 1..MushafStore.PAGE_COUNT || bookmark?.page == page) return
        bookmark = Bookmark(page, at)
        save()
    }

    fun remove() {
        if (bookmark == null) return
        bookmark = null
        save()
    }

    val snapshot: Snapshot get() = Snapshot(bookmark, maxOf(updatedAt, bookmark?.placedAt ?: Moment.DISTANT_PAST))

    fun apply(snapshot: Snapshot) {
        if (snapshot == this.snapshot) return
        bookmark = snapshot.bookmark?.takeIf { it.page in 1..MushafStore.PAGE_COUNT }
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
