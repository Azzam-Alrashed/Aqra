package com.azzamalrashed.aqra.revision

import com.azzamalrashed.aqra.TestQuran
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.ProgressJson
import com.azzamalrashed.aqra.memorization.AyahMemory
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.plan.PlanStore
import com.azzamalrashed.aqra.plan.TodayPortion
import kotlinx.serialization.Serializable
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.time.ZoneId

/**
 * shared/fixtures/schedule-parity.json, read by this test and by the iOS app's JourneyTests.scheduleParityFixture: the
 * same records, revision state, plan, moment and time zone give the same plan, strengths (to 1e-12), streak,
 * suggestions and next portion on both platforms.
 */
class ScheduleParityTest {
    @Serializable
    private data class Entry(val ayah: Int, val memory: AyahMemory)

    @Serializable
    private data class Outcome(
        /** Today's plan, as "page:kind". */
        val plan: List<String>,
        val strengths: Map<String, Double>,
        val streak: Int,
        val suggestions: List<Int>,
        val nextPortion: List<Int>,
    )

    @Serializable
    private data class Fixture(
        val zone: String,
        val now: Moment,
        val strengthAyahs: List<Int>,
        val ayahs: List<Entry>,
        val revision: RevisionStore.Snapshot,
        val plan: PlanStore.Snapshot,
        val expected: Outcome,
    )

    @Test
    fun scheduleParityFixture() {
        val file = File(TestQuran.directory, "../fixtures/schedule-parity.json")
        val fixture = ProgressJson.decodeFromString(Fixture.serializer(), file.readText())
        val zone = ZoneId.of(fixture.zone)
        val store = TestQuran.store
        val memorization = MemorizationStore(file = null)
        memorization.replaceAll(fixture.ayahs.associate { it.ayah to it.memory })
        val revision = RevisionStore(file = null, zone = zone)
        revision.apply(fixture.revision)
        val plan = PlanStore(file = null, zone = zone)
        plan.apply(fixture.plan)
        revision.refreshPlan(RevisionStore.memorizedPages(store, memorization), fixture.now)
        val portion = (plan.today(memorization, store, fixture.now) as? TodayPortion.Due)?.ayahs.orEmpty()
        val kinds = mapOf(PlanItem.Kind.FOLLOW_UP to "followUp", PlanItem.Kind.ROTATION to "rotation")
        val outcome = Outcome(
            plan = revision.plan?.items?.map { "${it.page}:${kinds[it.kind]}" }.orEmpty(),
            strengths = fixture.strengthAyahs.associate { it.toString() to (memorization.strength(it, fixture.now) ?: -1.0) },
            streak = revision.streak(fixture.now),
            suggestions = RotationAdvisor.suggestions(store, memorization, revision, emptyMap(), fixture.now),
            nextPortion = portion,
        )
        val computed = ProgressJson.encodeToString(Outcome.serializer(), outcome)
        val expected = fixture.expected
        assertEquals(computed, expected.plan, outcome.plan)
        assertEquals(computed, expected.streak, outcome.streak)
        assertEquals(computed, expected.suggestions, outcome.suggestions)
        assertEquals(computed, expected.nextPortion, outcome.nextPortion)
        assertEquals(computed, expected.strengths.keys, outcome.strengths.keys)
        for ((ayah, strength) in expected.strengths) assertEquals(computed, strength, outcome.strengths.getValue(ayah), 1e-12)
    }
}
