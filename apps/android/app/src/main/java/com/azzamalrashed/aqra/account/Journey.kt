package com.azzamalrashed.aqra.account

import com.azzamalrashed.aqra.core.ProgressJson
import com.azzamalrashed.aqra.curriculum.AssessmentStore
import com.azzamalrashed.aqra.plan.PlanStore
import com.azzamalrashed.aqra.rewards.RewardStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

/**
 * The rest of the student's journey beside what's memorized and the revision record: the personal plan, the rewards
 * and the stages' assessments. Backed up together as one document, `users/{uid}/journey/state`.
 */
class Journey(val plan: PlanStore, val rewards: RewardStore, val assessments: AssessmentStore) {
    /** Called after any of them changes, so the backup can follow. */
    var onChange: (() -> Unit)? = null
        set(value) {
            field = value
            plan.onChange = value
            rewards.onChange = value
            assessments.onChange = value
        }

    @Serializable
    data class Snapshot(
        val plan: PlanStore.Snapshot = PlanStore.Snapshot.EMPTY,
        val rewards: RewardStore.Snapshot = RewardStore.Snapshot.EMPTY,
        val assessments: AssessmentStore.Snapshot = AssessmentStore.Snapshot.EMPTY,
    ) {
        companion object {
            val EMPTY = Snapshot()

            fun merge(local: Snapshot, remote: Snapshot) = Snapshot(
                PlanStore.Snapshot.merge(local.plan, remote.plan),
                RewardStore.Snapshot.merge(local.rewards, remote.rewards),
                AssessmentStore.Snapshot.merge(local.assessments, remote.assessments),
            )
        }
    }

    val snapshot: Snapshot get() = Snapshot(plan.snapshot, rewards.snapshot, assessments.snapshot)

    fun apply(snapshot: Snapshot) {
        plan.apply(snapshot.plan)
        rewards.apply(snapshot.rewards)
        assessments.apply(snapshot.assessments)
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

        fun decode(json: String): Snapshot? = runCatching { ProgressJson.decodeFromString(Snapshot.serializer(), json) }.getOrNull()

        /** The account's copy as a JSON object, to carry what this app doesn't know; empty if it isn't one. */
        fun original(json: String): JsonObject =
            runCatching { ProgressJson.parseToJsonElement(json).jsonObject }.getOrNull() ?: JsonObject(emptyMap())
    }
}
