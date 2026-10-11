package com.azzamalrashed.aqra.mushaf

import com.azzamalrashed.aqra.quran.MushafStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Mushaf's pager, as a phone turns between one page and two facing pages (900 dp or wider in landscape). */
class MushafPagingTest {
    /**
     * Turning the phone changes how the pager counts, so it starts again from the page kept. That page must come back
     * on screen, and settling there must not count as a turn, so even an even page (the left of a spread) survives.
     */
    @Test
    fun rotatingKeepsThePage() {
        for (page in 1..MushafStore.PAGE_COUNT) {
            // To landscape: the pager restarts on the page's spread, which shows the page.
            val spread = MushafPaging.position(page, facing = true)
            assertTrue("page $page", page in MushafPaging.pages(spread, facing = true))
            assertTrue("page $page", MushafPaging.isSamePlace(spread, page, facing = true))
            // And back to portrait: on the page itself.
            val single = MushafPaging.position(page, facing = false)
            assertEquals(page, MushafPaging.page(single, facing = false))
            assertEquals(listOf(page), MushafPaging.pages(single, facing = false))
            assertTrue("page $page", MushafPaging.isSamePlace(single, page, facing = false))
        }
        // The spreads are the printed Mushaf's: 302 of them, the odd page on the right.
        assertEquals(302, MushafPaging.count(facing = true))
        assertEquals(604, MushafPaging.count(facing = false))
        assertEquals(listOf(45, 46), MushafPaging.pages(MushafPaging.position(46, facing = true), facing = true))
        assertEquals(45, MushafPaging.page(MushafPaging.position(46, facing = true), facing = true))
        // What a pager that kept its position through the turn showed: page 45's position, read as a spread, is pages 89 and 90.
        val kept = MushafPaging.position(45, facing = false)
        assertFalse(MushafPaging.isSamePlace(kept, 45, facing = true))
        assertEquals(listOf(89, 90), MushafPaging.pages(kept, facing = true))
    }
}
