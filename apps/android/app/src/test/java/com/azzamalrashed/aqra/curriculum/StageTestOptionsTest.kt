package com.azzamalrashed.aqra.curriculum

import com.azzamalrashed.aqra.TestQuran
import org.junit.Assert.assertEquals
import org.junit.Test

/** A stage test's options, as the iOS app's JourneyTests check them. */
class StageTestOptionsTest {
    @Test
    fun aStageTestsOptionsLeaveOutOnlyTheAyahEndMarker() {
        val store = TestQuran.store
        // Every ayah ends with its numbered marker; leaving it out removes that one word and nothing else.
        store.ayahTexts.forEachIndexed { index, text ->
            val number = store.reference(index).second
            assertEquals(text, ayahWithoutNumber(text) + " \u200F" + String(Character.toChars(0xE959 + number)))
        }
        // Text that doesn't end in a marker is left as it is.
        assertEquals("بسم الله", ayahWithoutNumber("بسم الله"))
    }
}
