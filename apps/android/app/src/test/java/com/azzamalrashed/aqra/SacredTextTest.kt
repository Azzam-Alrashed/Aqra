package com.azzamalrashed.aqra

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest

/** Guards the sacred texts against any change, however small: the same SHA-256 values as the iOS app's tests. */
class SacredTextTest {
    private fun sha256(text: String) = MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }

    /** SHA-256 of the hadith as published on https://dorar.net/hadith/sharh/116139 */
    @Test
    fun hadithMatchesSource() {
        assertEquals("603fc0da4a3d989fe2dfed4176da0fd60748accc83eb908c12bc8fee5ae77681", sha256(SacredText.RECITE_AND_ASCEND))
    }

    /** SHA-256 of the translation as published on https://sunnah.com/tirmidhi:2914 */
    @Test
    fun translationMatchesSource() {
        assertEquals("480209807cfb072ed78d8cca9a7bc32c481cb53e97d2b08e511c493bb084115c", sha256(SacredText.RECITE_AND_ASCEND_TRANSLATION))
    }

    @Test
    fun emphasisIsPartOfHadith() {
        assertTrue(SacredText.RECITE_AND_ASCEND.contains(SacredText.RECITE_AND_ASCEND_EMPHASIS))
    }
}
