package com.azzamalrashed.aqra.quran

/**
 * A word of a Mushaf page laid out in its page font, as CoreText lays it out on iOS: its characters' glyphs right to
 * left (they're Arabic presentation forms), with the font's kerning between them. In font units, y up.
 */
class WordLayout(
    /** The glyphs from left to right. */
    val glyphs: IntArray,
    /** Each glyph's x position from the word's left edge. */
    val positions: FloatArray,
    /** The word's advance: the room it takes on the line. */
    val width: Float,
) {
    companion object {
        fun of(text: String, font: SfntFont): WordLayout {
            val logical = text.codePoints().toArray().map(font::glyph)
            val count = logical.size
            // Each glyph's advance, with what the kerning of the pairs it's in adds to it.
            val advances = IntArray(count) { font.advance(logical[it]) }
            for (i in 0 until count - 1) {
                val (first, second) = font.kerning(logical[i], logical[i + 1])
                advances[i] += first
                advances[i + 1] += second
            }
            // Right to left: the last character is drawn first from the left.
            val glyphs = IntArray(count)
            val positions = FloatArray(count)
            var x = 0f
            for (j in 0 until count) {
                val i = count - 1 - j
                glyphs[j] = logical[i]
                positions[j] = x
                x += advances[i]
            }
            return WordLayout(glyphs, positions, x)
        }

        /**
         * A line of text in one of the Mushaf's text fonts, which map each character straight to its glyph (Hafs
         * Smart for the basmala and the ayat, the surah header font): glyph after glyph in the order the Unicode
         * bidirectional algorithm puts the characters, as CoreText does. Hafs Smart's characters are private-use ones,
         * which read left to right; the right-to-left mark before each one turns the line around, while two written
         * with no mark between them keep their order. The marks take no room and draw nothing.
         */
        fun ofText(text: String, font: SfntFont): WordLayout {
            val glyphs = visualOrder(text).filterNot(::isIgnorable).map(font::glyph).toIntArray()
            val positions = FloatArray(glyphs.size)
            var x = 0f
            for (j in glyphs.indices) {
                positions[j] = x
                x += font.advance(glyphs[j])
            }
            return WordLayout(glyphs, positions, x)
        }

        /** A line's characters from left to right, by the Unicode bidirectional algorithm. */
        private fun visualOrder(text: String): List<Int> {
            val bidi = java.text.Bidi(text, java.text.Bidi.DIRECTION_DEFAULT_LEFT_TO_RIGHT)
            val count = bidi.runCount
            val levels = ByteArray(count) { bidi.getRunLevel(it).toByte() }
            val runs = Array<Any>(count) { it }
            java.text.Bidi.reorderVisually(levels, 0, runs, 0, count)
            return runs.flatMap { run ->
                val index = run as Int
                val characters = text.substring(bidi.getRunStart(index), bidi.getRunLimit(index)).codePoints().toArray().toList()
                if (bidi.getRunLevel(index) % 2 == 1) characters.reversed() else characters
            }
        }

        /** Format characters that only steer the direction of the text. */
        private fun isIgnorable(codePoint: Int) =
            codePoint in 0x200B..0x200F || codePoint in 0x202A..0x202E || codePoint in 0x2066..0x2069 || codePoint == 0xFEFF
    }

    /** The word's plain outline: every glyph's own outline, in place. */
    fun outline(font: SfntFont): Outline {
        val builder = Outline.Builder()
        for (j in glyphs.indices) builder.add(font.outline(glyphs[j]).offset(positions[j], 0f))
        return builder.build()
    }

    /** The word's tajweed layers in drawing order: each layer's outline in place, and its palette entry. */
    fun colorLayers(font: SfntFont): List<Pair<Outline, Int>> = buildList {
        for (j in glyphs.indices) {
            for (layer in font.colorLayers[glyphs[j]].orEmpty()) {
                val entry = layer.entry ?: continue
                add(font.outline(layer.glyph).offset(positions[j], 0f) to entry)
            }
        }
    }
}
