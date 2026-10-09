package com.azzamalrashed.aqra.recitation

import com.azzamalrashed.aqra.quran.MushafLine
import com.azzamalrashed.aqra.quran.MushafPage
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.tasmee.MistakeType

/**
 * Follows a recitation through the words of a page: how far the student has reached, which ayat they stumbled on and
 * how, and the words a long pause brought them (the prompt, تلقين).
 *
 * It's given what the model heard, a stretch at a time, and places it among the words expected — a little before where
 * the student is (going back to correct) to well after it (skipping). It never decides what the words are: the page's
 * own words are the only ones shown. The same rules as the iOS app's tracker.
 */
class RecitationTracker(val words: List<Word>) {
    /** The ayah (0 until 6236) and the word's place in it (from 1), as the Mushaf numbers them, and the word as recited. */
    data class Word(val ayah: Int, val position: Int, val text: String)

    /** The next word expected: every word before it was heard, prompted or passed over. */
    var cursor = 0
        private set
    /** How far the stretch still being recited reaches, before it's settled. */
    var tentative = 0
        private set
    private val stumbleMap = LinkedHashMap<Int, MutableSet<MistakeType>>()
    val stumbles: Map<Int, Set<MistakeType>> get() = stumbleMap
    /** The words shown as prompts, by their index in [words]. */
    val prompted = LinkedHashSet<Int>()

    /**
     * Going back this many words or fewer to start again after a breath is reciting as it should be (الابتداء بما قبله);
     * further back is going back to correct.
     */
    var allowedRestart = 3

    /** How many words, from the first, are revealed. */
    val reached: Int get() = maxOf(cursor, tentative)

    val isComplete: Boolean get() = cursor >= words.size

    /** Whether the student is inside an ayah rather than between two. */
    val isMidAyah: Boolean get() = cursor > 0 && cursor < words.size && words[cursor].ayah == words[cursor - 1].ayah

    /**
     * What the model heard. A stretch still being recited ([final] false) only reveals the words it reaches; once the
     * student pauses, the whole stretch is settled: skipped words, wrong words and going back are stumbles.
     */
    fun hear(text: String, final: Boolean) {
        val heard = withoutOpening(RecitationText.normalizedWords(text))
        // A fragment of a letter or two (a word cut by a breath) says nothing either way.
        if (heard.isEmpty() || (heard.size == 1 && heard[0].length <= 2)) {
            if (final) tentative = cursor
            return
        }
        val matches = align(heard, words.map { it.text }, cursor)
        val matchedHeard = matches.sumOf { it.heard.last - it.heard.first + 1 }
        if (matches.isEmpty() || matchedHeard < maxOf(1, (heard.size + 1) / 2)) {
            // Little of it fits anywhere near: words that aren't the page's.
            if (final) {
                if (cursor < words.size) stumble(words[cursor].ayah, MistakeType.MEMORIZATION)
                tentative = cursor
            }
            return
        }
        val first = matches.first().expected.first
        val last = matches.last().expected.last + 1
        if (!final) {
            // Revealed only when it carries on from where the student is.
            if (first <= cursor) tentative = maxOf(tentative, last)
            return
        }
        if (first < cursor - allowedRestart) {
            stumble(words[first].ayah, MistakeType.HESITATION)
        } else if (first > cursor) {
            for (index in cursor until first) stumble(words[index].ayah, MistakeType.MEMORIZATION)
        }
        // Inside the stretch: words expected but not heard, and words heard that fit nowhere.
        val matched = matches.flatMap { it.expected.toList() }.toSet()
        for (index in maxOf(first, cursor) until last) {
            if (index !in matched) stumble(words[index].ayah, MistakeType.MEMORIZATION)
        }
        if (heard.size - matchedHeard >= 2) stumble(words[last - 1].ayah, MistakeType.MEMORIZATION)
        cursor = maxOf(cursor, last)
        tentative = cursor
    }

    /** A long pause: the next word is shown, and its ayah needed prompting. */
    fun prompt() {
        if (cursor >= words.size) return
        prompted += cursor
        stumble(words[cursor].ayah, MistakeType.PROMPTING)
        cursor += 1
        tentative = cursor
    }

    /**
     * A long pause inside an ayah that passed without a prompt (the student carried on by themselves before one could be
     * shown): a hesitation on that ayah.
     */
    fun hesitated() {
        if (isMidAyah) stumble(words[cursor].ayah, MistakeType.HESITATION)
    }

    /** The student revealed words by hand: carry on from there, without counting them. */
    fun skip(to: Int) {
        cursor = minOf(maxOf(cursor, to), words.size)
        tentative = maxOf(tentative, cursor)
    }

    /**
     * The isti'adha and the basmala a reciter says before reciting, or at the start of a surah, aren't words of the page
     * — unless the basmala is (al-Fatiha's first ayah).
     */
    private fun withoutOpening(heard: List<String>): List<String> {
        var rest = heard
        val expected = words.drop(minOf(cursor, words.size)).take(4).map { it.text }
        for (opening in listOf(ISTIADHA, BASMALA)) {
            if (opening == expected) continue
            if (rest.size >= opening.size && rest.zip(opening).all { (a, b) -> RecitationText.similarity(a, b) >= 0.75 }) {
                rest = rest.drop(opening.size)
            }
        }
        return rest
    }

    private fun stumble(ayah: Int, type: MistakeType) {
        stumbleMap.getOrPut(ayah) { LinkedHashSet() } += type
    }

    /** A run of heard words matched to a run of expected ones (one to one, two to one or one to two). */
    data class Match(val heard: IntRange, val expected: IntRange)

    companion object {
        private val ISTIADHA = listOf("اعوذ", "بالله", "من", "الشيطان", "الرجيم")
        private val BASMALA = listOf("بسم", "الله", "الرحمن", "الرحيم")

        /**
         * Where heard words fit among the expected ones, searched from a little before [cursor] to well after it. Every
         * heard word is placed, matched or left over; the expected words around them are free to skip. Exact matches beat
         * near ones and long words short ones, two heard words may make one expected word or one heard word two (the
         * model and the Mushaf don't always split words alike), and starting ahead of the cursor, or skipping words inside
         * the run, costs more than going back a little. Returns the matched runs in order.
         */
        fun align(heard: List<String>, expected: List<String>, cursor: Int, back: Int = 12, ahead: Int = 40): List<Match> {
            val low = maxOf(0, minOf(cursor, expected.size) - back)
            val high = minOf(expected.size, cursor + ahead)
            if (high <= low) return emptyList()
            val window = expected.subList(low, high)
            val n = heard.size
            val m = window.size
            if (n == 0 || m == 0) return emptyList()

            fun score(a: String, b: String): Double? {
                // A short word says less about where the student is than a long one: «في» is on every page.
                val shorter = minOf(a.length, b.length)
                val weight = 0.5 + 0.125 * minOf(shorter, 4)
                if (a == b) return 2 * weight
                // Short words must be closer: «أيكم» isn't «إياك».
                val needed = if (shorter <= 4) 0.85 else 0.75
                return if (RecitationText.similarity(a, b) >= needed) 1.4 * weight else null
            }

            val best = Array(n + 1) { DoubleArray(m + 1) { Double.NEGATIVE_INFINITY } }
            val step = Array(n + 1) { IntArray(m + 1) { START } }
            // Starting ahead of the student says words were skipped, so it costs more than going back a little.
            for (j in 0..m) {
                val start = low + j
                best[0][j] = if (start < cursor) -0.05 * (cursor - start) else -0.5 * (start - cursor)
            }
            for (i in 1..n) {
                for (j in 0..m) {
                    var value = best[i - 1][j] - 1
                    var how = SKIP_HEARD
                    fun consider(candidate: Double, move: Int) {
                        if (candidate > value) {
                            value = candidate
                            how = move
                        }
                    }
                    if (j > 0) {
                        consider(best[i][j - 1] - 1.5, SKIP_EXPECTED)
                        val s = score(heard[i - 1], window[j - 1])
                        if (s != null) consider(best[i - 1][j - 1] + s, MATCH) else consider(best[i - 1][j - 1] - 1, MISMATCH)
                        if (i > 1) score(heard[i - 2] + heard[i - 1], window[j - 1])?.let { consider(best[i - 2][j - 1] + it - 0.2, JOIN_HEARD) }
                        if (j > 1) score(heard[i - 1], window[j - 2] + window[j - 1])?.let { consider(best[i - 1][j - 2] + it - 0.2, JOIN_EXPECTED) }
                    }
                    best[i][j] = value
                    step[i][j] = how
                }
            }
            var j = (0..m).maxByOrNull { best[n][it] } ?: 0
            var i = n
            val runs = ArrayList<Match>()
            while (i > 0) {
                when (step[i][j]) {
                    SKIP_HEARD -> i -= 1
                    SKIP_EXPECTED -> j -= 1
                    MISMATCH -> { i -= 1; j -= 1 }
                    MATCH -> { runs += Match(i - 1..i - 1, low + j - 1..low + j - 1); i -= 1; j -= 1 }
                    JOIN_HEARD -> { runs += Match(i - 2..i - 1, low + j - 1..low + j - 1); i -= 2; j -= 1 }
                    JOIN_EXPECTED -> { runs += Match(i - 1..i - 1, low + j - 2..low + j - 1); i -= 1; j -= 2 }
                    else -> i = 0
                }
            }
            return runs.reversed()
        }

        private const val START = 0
        private const val SKIP_HEARD = 1
        private const val SKIP_EXPECTED = 2
        private const val MATCH = 3
        private const val MISMATCH = 4
        private const val JOIN_HEARD = 5
        private const val JOIN_EXPECTED = 6

        /**
         * Following the revision of a page: the words of the ayat it covers, as far as they're on this page (an ayah can
         * begin on the page before or end on the next), in reading order.
         */
        fun forPage(page: MushafPage, ayahs: List<Int>, store: MushafStore): RecitationTracker {
            val covered = ayahs.toSet()
            val spoken = HashMap<Int, List<String>>()
            val words = ArrayList<Word>()
            for (line in page.lines) {
                val lineWords = (line.kind as? MushafLine.Kind.Ayah)?.words ?: continue
                for (word in lineWords) {
                    if (word.isAyahEnd || word.ayah !in covered) continue
                    val texts = spoken.getOrPut(word.ayah) {
                        RecitationText.wordsOfAyah(store.ayahPlainTexts[word.ayah], store.ayahWordCounts[word.ayah])
                    }
                    val text = texts.getOrNull(word.position - 1) ?: continue
                    words += Word(word.ayah, word.position, text)
                }
            }
            return RecitationTracker(words)
        }
    }
}
