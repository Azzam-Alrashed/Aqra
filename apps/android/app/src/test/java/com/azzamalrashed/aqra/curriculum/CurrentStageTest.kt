package com.azzamalrashed.aqra.curriculum

import com.azzamalrashed.aqra.TestDates.day
import com.azzamalrashed.aqra.TestDates.utc
import com.azzamalrashed.aqra.TestQuran
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.plan.MemorizationPlan
import com.azzamalrashed.aqra.plan.PlanStore
import org.junit.Assert.assertEquals
import org.junit.Test

/** The home's stage, as the iOS app's JourneyTests check it. */
class CurrentStageTest {
    @Test
    fun theCurrentStageStaysSteadyThroughTheDay() {
        val store = TestQuran.store
        val memorization = MemorizationStore(file = null)
        val plan = PlanStore(file = null, zone = utc)
        val ammaStart = store.juzAyahs.getValue(30).first
        // Declaring what's already known doesn't move it, whatever was marked last: al-Fatiha after juz' ʿAmma.
        memorization.mark(ammaStart..ammaStart + 20, memorized = true)
        memorization.mark(0..6, memorized = true)
        assertEquals(1, AssessmentStore.currentStage(null, memorization, store, emptyMap()))
        // An ayah memorized in Aqra leads it.
        memorization.learn(listOf(ammaStart + 30), at = day(1), stability = 2.0)
        assertEquals(10, AssessmentStore.currentStage(null, memorization, store, emptyMap()))
        // With a plan, the next portion leads it, whether or not today's portion is due, and while it's paused.
        plan.setPlan(MemorizationPlan(8, (1..7).toSet(), MemorizationPlan.Order.FROM_START), now = day(0))
        val next = plan.nextAyah(memorization, store)!!
        assertEquals(1, store.juzOfAyah(next))
        assertEquals(1, AssessmentStore.currentStage(next, memorization, store, emptyMap()))
        plan.setPlan(plan.plan!!.copy(paused = true), now = day(1))
        assertEquals(next, plan.nextAyah(memorization, store))
    }
}
