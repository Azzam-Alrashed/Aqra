package com.azzamalrashed.aqra.revision

import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.quran.MushafStore

/**
 * The far lane learns: pages that keep slipping — stumbled on in more than one revision lately, or faint while the
 * rest is strong — are suggested for extra follow-up, and the student approves or dismisses each suggestion
 * (docs/REVISION.md, open question 3).
 */
object RotationAdvisor {
    /** A page stumbled on in at least this many revisions in the window is slipping. */
    const val STUMBLED_REVISIONS = 2
    const val WINDOW = 30 * 86_400.0
    /** A page this faint is slipping when the memorization as a whole is at least [STRONG_AVERAGE]. */
    const val FAINT = 0.35
    const val STRONG_AVERAGE = 0.5
    /** A dismissed suggestion comes back no sooner than this. */
    const val SNOOZE = 14 * 86_400.0

    /** [dismissed]: until when each page's suggestion was dismissed. */
    fun suggestions(
        store: MushafStore,
        memorization: MemorizationStore,
        revision: RevisionStore,
        dismissed: Map<Int, Moment>,
        now: Moment = Moment.now(),
        limit: Int = 3,
    ): List<Int> {
        val pages = RevisionStore.memorizedPages(store, memorization)
        if (pages.size < 5) return emptyList()
        val planned = revision.plan?.items?.map { it.page }.orEmpty().toSet()
        val stumbled = HashMap<Int, Int>()
        for (record in revision.history) {
            if (now - record.date < WINDOW && record.stumbles.isNotEmpty()) stumbled[record.page] = (stumbled[record.page] ?: 0) + 1
        }
        val ayahs = memorization.ayahs
        val strengths = pages.associateWith { page ->
            val values = store.page(page).ayahs.mapNotNull { ayahs[it]?.strength(now) }
            if (values.isEmpty()) 1.0 else values.average()
        }
        val overall = strengths.values.sum() / maxOf(strengths.size, 1)
        return pages
            .filter { page ->
                revision.followUps[page] == null && page !in planned && (dismissed[page] ?: Moment.DISTANT_PAST) <= now &&
                    ((stumbled[page] ?: 0) >= STUMBLED_REVISIONS || ((strengths[page] ?: 1.0) < FAINT && overall >= STRONG_AVERAGE))
            }
            .sortedWith(compareByDescending<Int> { stumbled[it] ?: 0 }.thenBy { strengths[it] ?: 1.0 })
            .take(limit)
            .sorted()
    }

    /** The student took the suggestion: the pages come back for follow-up from tomorrow. */
    fun accept(pages: List<Int>, revision: RevisionStore, now: Moment = Moment.now()) = revision.followUp(pages, now)

    /** The student dismissed it: the pages aren't suggested again for a while. Returns what's dismissed now. */
    fun dismiss(pages: List<Int>, dismissed: Map<Int, Moment>, now: Moment = Moment.now()): Map<Int, Moment> =
        (dismissed + pages.associateWith { now + SNOOZE }).filterValues { it > now }
}
