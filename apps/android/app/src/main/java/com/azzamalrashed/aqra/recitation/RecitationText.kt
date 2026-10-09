package com.azzamalrashed.aqra.recitation

/**
 * What a student says when reciting an ayah, taken from the Complex's official Imla'i text and matched to the words of
 * the Mushaf. It's only used to follow a recitation; the page always shows the Mushaf's own words.
 */
object RecitationText {
    /**
     * Plain words the Mushaf writes joined to the word after them: «أو لا» is «أَوَلَا», «ها أنتم» is «هَٰٓأَنتُمْ», «إل ياسين» is
     * «إِلۡيَاسِينَ». Only where the ayah's word count says so: «أو» on its own stays a word.
     */
    private val joining = setOf("أو", "ها", "إل")

    /** One normalized word for each word of the Mushaf in an ayah ([mushafWords] of them, the ayah-end marker left out). */
    fun wordsOfAyah(plain: String, mushafWords: Int): List<String> {
        val tokens = plain.replace("‎", "").replace("‏", "").split(' ').filter { it.isNotEmpty() }
        val excess = tokens.size - mushafWords
        var joined = emptySet<Int>()
        if (excess > 0) {
            var candidates = tokens.indices.toList().dropLast(1).filter { tokens[it] in joining }
            if (candidates.size > excess) {
                // Where it's ambiguous (al-A'raf 7:88, at-Tawbah 9:126) the Mushaf joins «أو» to a short particle
                // («أَوَلَوۡ», «أَوَلَا»), not to the longer word after another «أو».
                val short = candidates.filter { tokens[it + 1].length <= 2 }
                if (short.size >= excess) candidates = short
            }
            joined = candidates.take(excess).toSet()
        }
        val words = ArrayList<String>()
        val pending = StringBuilder()
        for ((index, token) in tokens.withIndex()) {
            pending.append(normalize(token))
            if (index !in joined) {
                words += pending.toString()
                pending.clear()
            }
        }
        return words
    }

    /** Recited text as normalized words: what the model heard, ready to compare with the ayat. */
    fun normalizedWords(text: String): List<String> =
        text.split(Regex("\\s+")).map(::normalize).filter { it.isNotEmpty() }

    /**
     * A word without tashkeel, Quranic marks or tatweel, with one form of alef, ya for alef maqsura, ha for ta marbuta
     * and the seated hamzas on their seat, and nothing that isn't an Arabic letter.
     */
    fun normalize(word: String): String {
        val out = StringBuilder(word.length)
        for (char in word) {
            when (char.code) {
                in 0x0610..0x061A, in 0x064B..0x065F, 0x0670, in 0x06D6..0x06ED, 0x0640 -> continue
                0x0622, 0x0623, 0x0625, 0x0671 -> out.append('ا')
                0x0649, 0x0626 -> out.append('ي')
                0x0629 -> out.append('ه')
                0x0624 -> out.append('و')
                in 0x0621..0x064A -> out.append(char)
                else -> continue
            }
        }
        return out.toString()
    }

    /** How alike two normalized words are, from 0 to 1: the share of their letters left after the fewest edits. */
    fun similarity(a: String, b: String): Double {
        if (a == b) return 1.0
        if (a.isEmpty() || b.isEmpty()) return 0.0
        var previous = IntArray(b.length + 1) { it }
        var current = IntArray(b.length + 1)
        for (i in 1..a.length) {
            current[0] = i
            for (j in 1..b.length) {
                current[j] = minOf(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + if (a[i - 1] == b[j - 1]) 0 else 1)
            }
            val swap = previous
            previous = current
            current = swap
        }
        val total = (a.length + b.length).toDouble()
        return (total - previous[b.length]) / total
    }
}
