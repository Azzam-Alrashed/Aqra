package com.azzamalrashed.aqra.quran

import org.brotli.dec.BrotliInputStream
import java.io.ByteArrayInputStream

/**
 * Reads a WOFF2 font (https://www.w3.org/TR/WOFF2/) into its tables, as the font's own bytes, without writing a
 * font file: the Mushaf page fonts are bundled exactly as published, and Android can't load WOFF2 itself.
 *
 * Tables stored as they are (every table but `glyf` and `loca` in the page fonts) come back byte for byte. The
 * glyph outlines, stored in WOFF2's transformed form, are decoded into [GlyphData] values instead of being
 * re-encoded as a `glyf` table, since only their outlines are drawn.
 */
class Woff2Font private constructor(
    val tables: Map<String, ByteArray>,
    /** The outlines, when the font's `glyf` table was transformed; null when it's stored as a plain `glyf`. */
    val transformedGlyphs: Array<GlyphData>?,
) {
    companion object {
        private const val SIGNATURE = 0x774F4632 // 'wOF2'

        private val KNOWN_TAGS = listOf(
            "cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post", "cvt ", "fpgm", "glyf", "loca", "prep",
            "CFF ", "VORG", "EBDT", "EBLC", "gasp", "hdmx", "kern", "LTSH", "PCLT", "VDMX", "vhea", "vmtx", "BASE",
            "GDEF", "GPOS", "GSUB", "EBSC", "JSTF", "MATH", "CBDT", "CBLC", "COLR", "CPAL", "SVG ", "sbix", "acnt",
            "avar", "bdat", "bloc", "bsln", "cvar", "fdsc", "feat", "fmtx", "fvar", "gvar", "hsty", "just", "lcar",
            "mort", "morx", "opbd", "prop", "trak", "Zapf", "Silf", "Glat", "Gloc", "Feat", "Sill",
        )

        fun read(bytes: ByteArray): Woff2Font {
            val header = Bytes(bytes)
            require(header.u32(0) == SIGNATURE) { "Not a WOFF2 font" }
            val flavor = header.u32(4)
            require(flavor != 0x74746366) { "Font collections aren't supported" } // 'ttcf'
            val numTables = header.u16(12)
            val totalCompressedSize = header.u32(20)

            class Entry(val tag: String, val transformed: Boolean, val length: Int)

            var offset = 48
            val entries = ArrayList<Entry>(numTables)
            repeat(numTables) {
                val flags = bytes[offset++].toInt() and 0xFF
                val tagIndex = flags and 0x3F
                val tag = if (tagIndex == 63) {
                    String(bytes, offset, 4, Charsets.ISO_8859_1).also { offset += 4 }
                } else {
                    KNOWN_TAGS[tagIndex]
                }
                val version = flags shr 6
                val origLength = base128(bytes, offset).also { offset = it.second }.first
                // glyf and loca are transformed unless their version is 3; every other table only when it's not 0.
                val transformed = if (tag == "glyf" || tag == "loca") version != 3 else version != 0
                val length = if (transformed) base128(bytes, offset).also { offset = it.second }.first else origLength
                entries += Entry(tag, transformed, length)
            }

            val data = BrotliInputStream(ByteArrayInputStream(bytes, offset, totalCompressedSize)).use { it.readBytes() }
            val tables = LinkedHashMap<String, ByteArray>()
            val transformedTables = HashMap<String, ByteArray>()
            var position = 0
            for (entry in entries) {
                require(position + entry.length <= data.size) { "Truncated table ${entry.tag}" }
                val table = data.copyOfRange(position, position + entry.length)
                position += entry.length
                if (entry.transformed) transformedTables[entry.tag] = table else tables[entry.tag] = table
            }
            transformedTables["hmtx"]?.let { hmtx ->
                // Only the advances are needed; a transformed hmtx keeps them as they are, ahead of the side bearings.
                tables["hmtx"] = hmtx.copyOfRange(1, hmtx.size)
            }
            val glyphs = transformedTables["glyf"]?.let { decodeGlyf(it) }
            return Woff2Font(tables, glyphs)
        }

        /** WOFF2's UIntBase128: the value and the offset after it. */
        private fun base128(bytes: ByteArray, start: Int): Pair<Int, Int> {
            var value = 0L
            var offset = start
            for (i in 0 until 5) {
                val byte = bytes[offset++].toInt() and 0xFF
                require(!(i == 0 && byte == 0x80)) { "Bad UIntBase128" }
                value = (value shl 7) or (byte and 0x7F).toLong()
                require(value <= 0xFFFFFFFFL) { "Bad UIntBase128" }
                if (byte and 0x80 == 0) return value.toInt() to offset
            }
            error("Bad UIntBase128")
        }

        /** The transformed `glyf` table (WOFF2 §5.1), decoded glyph by glyph. */
        private fun decodeGlyf(table: ByteArray): Array<GlyphData> {
            val header = Bytes(table)
            val numGlyphs = header.u16(4)
            val sizes = IntArray(7) { header.u32(8 + 4 * it) }
            var start = 8 + 4 * 7
            val streams = sizes.map { size -> Stream(table, start, size).also { start += size } }
            val (nContourStream, nPointsStream, flagStream, glyphStream, compositeStream, bboxStream, instructionStream) =
                streams
            val bboxBitmapSize = 4 * ((numGlyphs + 31) / 32)
            val bboxBitmap = table.copyOfRange(bboxStream.position, bboxStream.position + bboxBitmapSize)
            bboxStream.skip(bboxBitmapSize)

            return Array(numGlyphs) { glyph ->
                val contours = nContourStream.s16()
                val hasBox = (bboxBitmap[glyph shr 3].toInt() and (0x80 shr (glyph and 7))) != 0
                val box = if (hasBox) IntArray(4) { bboxStream.s16() } else null
                when {
                    contours == 0 -> GlyphData.Empty
                    contours > 0 -> {
                        val ends = IntArray(contours)
                        var total = 0
                        for (c in 0 until contours) {
                            total += nPointsStream.u255()
                            ends[c] = total - 1
                        }
                        val xs = IntArray(total)
                        val ys = IntArray(total)
                        val onCurve = BooleanArray(total)
                        var x = 0
                        var y = 0
                        for (p in 0 until total) {
                            val flag = flagStream.u8()
                            onCurve[p] = flag and 0x80 == 0
                            val (dx, dy) = triplet(flag and 0x7F, glyphStream)
                            x += dx
                            y += dy
                            xs[p] = x
                            ys[p] = y
                        }
                        instructionStream.skip(glyphStream.u255())
                        GlyphData.Simple(ends, xs, ys, onCurve)
                    }
                    else -> {
                        requireNotNull(box) { "A composite glyph without its bounding box" }
                        val (components, hasInstructions) = parseComponents(compositeStream)
                        if (hasInstructions) instructionStream.skip(glyphStream.u255())
                        GlyphData.Composite(components)
                    }
                }
            }
        }

        /** A point's offset from the one before, from its flag and the bytes it takes (WOFF2 §5.2). */
        private fun triplet(flag: Int, stream: Stream): Pair<Int, Int> {
            fun sign(bit: Int, value: Int) = if (bit and 1 != 0) value else -value
            return when {
                flag < 10 -> 0 to sign(flag, ((flag and 14) shl 7) + stream.u8())
                flag < 20 -> sign(flag, (((flag - 10) and 14) shl 7) + stream.u8()) to 0
                flag < 84 -> {
                    val b0 = flag - 20
                    val b1 = stream.u8()
                    sign(flag, 1 + (b0 and 0x30) + (b1 shr 4)) to sign(flag shr 1, 1 + ((b0 and 0x0C) shl 2) + (b1 and 0x0F))
                }
                flag < 120 -> {
                    val b0 = flag - 84
                    val b1 = stream.u8()
                    val b2 = stream.u8()
                    sign(flag, 1 + ((b0 / 12) shl 8) + b1) to sign(flag shr 1, 1 + (((b0 % 12) shr 2) shl 8) + b2)
                }
                flag < 124 -> {
                    val b1 = stream.u8()
                    val b2 = stream.u8()
                    val b3 = stream.u8()
                    sign(flag, (b1 shl 4) + (b2 shr 4)) to sign(flag shr 1, ((b2 and 0x0F) shl 8) + b3)
                }
                else -> {
                    val dx = (stream.u8() shl 8) + stream.u8()
                    val dy = (stream.u8() shl 8) + stream.u8()
                    sign(flag, dx) to sign(flag shr 1, dy)
                }
            }
        }

        private operator fun <T> List<T>.component6() = this[5]
        private operator fun <T> List<T>.component7() = this[6]
    }

    /** A read position in one of the transformed glyf table's streams. */
    private class Stream(private val bytes: ByteArray, start: Int, size: Int) : ByteSource {
        var position = start
            private set
        private val end = start + size

        override fun u8(): Int {
            require(position < end) { "Truncated glyph stream" }
            return bytes[position++].toInt() and 0xFF
        }

        fun u16(): Int = (u8() shl 8) or u8()
        fun s16(): Int = u16().toShort().toInt()

        /** WOFF2's 255UInt16. */
        fun u255(): Int = when (val code = u8()) {
            253 -> u16()
            254 -> u8() + 506
            255 -> u8() + 253
            else -> code
        }

        fun skip(count: Int) {
            require(position + count <= end) { "Truncated glyph stream" }
            position += count
        }
    }
}

/** One glyph's outline data, before it's turned into curves. */
sealed class GlyphData {
    data object Empty : GlyphData()

    /** TrueType points: each contour ends at the index in [ends]; off-curve points are quadratic controls. */
    class Simple(val ends: IntArray, val xs: IntArray, val ys: IntArray, val onCurve: BooleanArray) : GlyphData()

    class Composite(val components: List<Component>) : GlyphData()
}

/** A composite glyph's part: another glyph, moved by (dx, dy) after the 2×2 transform. */
class Component(
    val glyph: Int,
    val dx: Float, val dy: Float,
    val a: Float, val b: Float, val c: Float, val d: Float,
    /** Whether the offset is scaled by the transform too (the Apple convention, SCALED_COMPONENT_OFFSET). */
    val scaledOffset: Boolean,
)

private const val ARG_1_AND_2_ARE_WORDS = 0x0001
private const val ARGS_ARE_XY_VALUES = 0x0002
private const val WE_HAVE_A_SCALE = 0x0008
private const val MORE_COMPONENTS = 0x0020
private const val WE_HAVE_AN_X_AND_Y_SCALE = 0x0040
private const val WE_HAVE_A_TWO_BY_TWO = 0x0080
private const val WE_HAVE_INSTRUCTIONS = 0x0100
private const val SCALED_COMPONENT_OFFSET = 0x0800

/** Bytes read one at a time, from a WOFF2 stream or a plain `glyf` table. */
internal fun interface ByteSource {
    fun u8(): Int
}

/** Reads bytes from a plain array, such as a `glyf` table that wasn't transformed. */
internal class ArraySource(private val bytes: ByteArray, var position: Int) : ByteSource {
    override fun u8(): Int = bytes[position++].toInt() and 0xFF
}

/** A composite glyph's components, in the TrueType format (the same inside WOFF2's composite stream), and whether
 *  it carries instructions. */
internal fun parseComponents(source: ByteSource): Pair<List<Component>, Boolean> {
    fun u8() = source.u8()
    fun u16() = (u8() shl 8) or u8()
    fun s16() = u16().toShort().toInt()
    fun f2dot14() = s16() / 16384f
    val components = ArrayList<Component>()
    var hasInstructions = false
    do {
        val flags = u16()
        val glyph = u16()
        require(flags and ARGS_ARE_XY_VALUES != 0) { "Composite glyphs placed by matching points aren't supported" }
        val (dx, dy) = if (flags and ARG_1_AND_2_ARE_WORDS != 0) s16() to s16() else u8().toByte().toInt() to u8().toByte().toInt()
        var a = 1f
        var b = 0f
        var c = 0f
        var d = 1f
        when {
            flags and WE_HAVE_A_SCALE != 0 -> { a = f2dot14(); d = a }
            flags and WE_HAVE_AN_X_AND_Y_SCALE != 0 -> { a = f2dot14(); d = f2dot14() }
            flags and WE_HAVE_A_TWO_BY_TWO != 0 -> { a = f2dot14(); b = f2dot14(); c = f2dot14(); d = f2dot14() }
        }
        if (flags and WE_HAVE_INSTRUCTIONS != 0) hasInstructions = true
        components += Component(glyph, dx.toFloat(), dy.toFloat(), a, b, c, d, flags and SCALED_COMPONENT_OFFSET != 0)
    } while (flags and MORE_COMPONENTS != 0)
    return components to hasInstructions
}

/** Big-endian reads from a table's bytes. */
internal class Bytes(val data: ByteArray) {
    fun u8(offset: Int): Int = data[offset].toInt() and 0xFF
    fun u16(offset: Int): Int = if (offset + 2 > data.size) 0 else (u8(offset) shl 8) or u8(offset + 1)
    fun s16(offset: Int): Int = u16(offset).toShort().toInt()
    fun u32(offset: Int): Int = (u16(offset) shl 16) or u16(offset + 2)
    val size: Int get() = data.size
}
