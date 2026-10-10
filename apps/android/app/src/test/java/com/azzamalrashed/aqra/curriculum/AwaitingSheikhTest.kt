package com.azzamalrashed.aqra.curriculum

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** A stage met but for the sheikh's test waits for one, as the iOS app's JourneyTests check it. */
class AwaitingSheikhTest {
    @Test
    fun aStageAwaitsTheSheikhOnceTheRestIsMet() {
        val progress = StageProgress(stage = 10, ayahs = 0..99, memorized = 100, mastered = 90, verified = 0)
        var status = StageStatus(progress, testPassed = true, bestScore = 1.0, sheikhPassed = false, passedAt = null, retestAt = null, policy = StagePolicy.STANDARD)
        assertTrue(status.awaitsSheikh && !status.meetsAll)
        assertFalse(status.copy(testPassed = false).awaitsSheikh)
        status = status.copy(policy = status.policy.copy(sheikhTestRequired = false))
        assertTrue(!status.awaitsSheikh && status.meetsAll)
        val assessments = AssessmentStore(file = null)
        assessments.setSheikhTestRequired(false)
        assertFalse(assessments.policy.sheikhTestRequired)
    }
}
