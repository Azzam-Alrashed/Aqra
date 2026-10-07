package com.azzamalrashed.aqra.quran

/**
 * A TrueType font read from its own tables, the way the Mushaf needs it: each character's glyph, each glyph's
 * advance and outline, the kerning between glyphs, and the tajweed colors (COLR version 0 and CPAL). Nothing in the
 * font is changed; it's only read.
 *
 * Pure Kotlin, with no Android types, so the tests check it on every page font against the official data.
 */
class SfntFont private constructor(
    private val tables: Map<String, ByteArray>,
    private val transformedGlyphs: Array<GlyphData>?,
) {
    companion object {
        private val NO_KERNING = 0 to 0
        private const val X_ADVANCE = 0x0004

        /** A font from a WOFF2 file (the Mushaf page fonts). */
        fun fromWoff2(bytes: ByteArray): SfntFont = Woff2Font.read(bytes).let { SfntFont(it.tables, it.transformedGlyphs) }

        /** A font from a TrueType file. */
        fun fromTrueType(bytes: ByteArray): SfntFont {
            val file = Bytes(bytes)
            val numTables = file.u16(4)
            val tables = HashMap<String, ByteArray>()
            for (i in 0 until numTables) {
                val record = 12 + 16 * i
                val tag = String(bytes, record, 4, Charsets.ISO_8859_1)
                val offset = file.u32(record + 8)
                val length = file.u32(record + 12)
                tables[tag] = bytes.copyOfRange(offset, offset + length)
            }
            return SfntFont(tables, null)
        }
    }

    private val head = Bytes(table("head"))
    private val hhea = Bytes(table("hhea"))

    val unitsPerEm: Int = head.u16(18)
    /** The vertical metrics, in font units: CoreText's ascent, descent and leading come from `hhea`. */
    val ascender: Int = hhea.s16(4)
    val descender: Int = hhea.s16(6)
    val lineGap: Int = hhea.s16(8)
    val glyphCount: Int = Bytes(table("maxp")).u16(4)

    private val advances: IntArray = run {
        val metrics = hhea.u16(34)
        val hmtx = Bytes(table("hmtx"))
        val advances = IntArray(glyphCount)
        var last = 0
        for (glyph in 0 until glyphCount) {
            if (glyph < metrics) last = hmtx.u16(4 * glyph)
            advances[glyph] = last
        }
        advances
    }

    private val characterGlyphs: Map<Int, Int> = readCmap(Bytes(table("cmap")))
    private val glyphs = arrayOfNulls<GlyphData>(glyphCount)
    private val outlines = arrayOfNulls<Outline>(glyphCount)
    /** Pair adjustments by (first, second) glyph: what each one's advance gains. */
    private val kerning: Map<Long, Pair<Int, Int>> = tables["GPOS"]?.let { readKerning(Bytes(it)) } ?: emptyMap()

    fun hasTable(tag: String): Boolean = tag in tables

    private fun table(tag: String): ByteArray = requireNotNull(tables[tag]) { "The font has no $tag table" }

    fun glyph(codePoint: Int): Int = characterGlyphs[codePoint] ?: 0

    fun advance(glyph: Int): Int = advances.getOrElse(glyph) { 0 }

    /** The kerning between two glyphs in reading order: what the first's advance and the second's advance gain. */
    fun kerning(first: Int, second: Int): Pair<Int, Int> = kerning[(first.toLong() shl 32) or second.toLong()] ?: NO_KERNING

    // MARK: - Outlines

    /** A glyph's outline in font units, y up from the baseline. */
    fun outline(glyph: Int): Outline {
        outlines.getOrNull(glyph)?.let { return it }
        val builder = Outline.Builder()
        addGlyph(glyph, builder, Transform.IDENTITY, depth = 0)
        return builder.build().also { if (glyph in outlines.indices) outlines[glyph] = it }
    }

    private fun glyphData(glyph: Int): GlyphData {
        if (glyph !in 0 until glyphCount) return GlyphData.Empty
        glyphs[glyph]?.let { return it }
        val data = transformedGlyphs?.getOrNull(glyph) ?: readGlyf(glyph)
        glyphs[glyph] = data
        return data
    }

    private fun addGlyph(glyph: Int, builder: Outline.Builder, transform: Transform, depth: Int) {
        require(depth < 8) { "Composite glyphs nested too deeply" }
        when (val data = glyphData(glyph)) {
            GlyphData.Empty -> Unit
            is GlyphData.Simple -> builder.addContours(data, transform)
            is GlyphData.Composite -> for (component in data.components) {
                val offset = if (component.scaledOffset) {
                    transform.apply(
                        component.a * component.dx + component.c * component.dy,
                        component.b * component.dx + component.d * component.dy,
                    )
                } else {
                    transform.apply(component.dx, component.dy)
                }
                val inner = Transform(
                    a = transform.a * component.a + transform.c * component.b,
                    b = transform.b * component.a + transform.d * component.b,
                    c = transform.a * component.c + transform.c * component.d,
                    d = transform.b * component.c + transform.d * component.d,
                    tx = offset.first, ty = offset.second,
                )
                addGlyph(component.glyph, builder, inner, depth + 1)
            }
        }
    }

    /** A glyph from a plain `glyf` table, located through `loca`. */
    private fun readGlyf(glyph: Int): GlyphData {
        val loca = Bytes(table("loca"))
        val long = head.s16(50) == 1
        val start = if (long) loca.u32(4 * glyph) else 2 * loca.u16(2 * glyph)
        val end = if (long) loca.u32(4 * glyph + 4) else 2 * loca.u16(2 * glyph + 2)
        if (end <= start) return GlyphData.Empty
        val glyf = Bytes(table("glyf"))
        val contours = glyf.s16(start)
        if (contours < 0) return GlyphData.Composite(parseComponents(ArraySource(glyf.data, start + 10)).first)
        val ends = IntArray(contours) { glyf.u16(start + 10 + 2 * it) }
        val total = if (contours == 0) 0 else ends.last() + 1
        var offset = start + 10 + 2 * contours
        offset += 2 + glyf.u16(offset) // the instructions
        val flags = IntArray(total)
        var p = 0
        while (p < total) {
            val flag = glyf.u8(offset++)
            flags[p++] = flag
            if (flag and 0x08 != 0) {
                repeat(glyf.u8(offset++)) { if (p < total) flags[p++] = flag }
            }
        }
        fun coordinates(short: Int, same: Int): IntArray {
            var value = 0
            return IntArray(total) { i ->
                val flag = flags[i]
                value += when {
                    flag and short != 0 -> glyf.u8(offset++).let { if (flag and same != 0) it else -it }
                    flag and same != 0 -> 0
                    else -> glyf.s16(offset).also { offset += 2 }
                }
                value
            }
        }
        val xs = coordinates(0x02, 0x10)
        val ys = coordinates(0x04, 0x20)
        return GlyphData.Simple(ends, xs, ys, BooleanArray(total) { flags[it] and 1 != 0 })
    }

    // MARK: - Tajweed colors

    /** A colored glyph's layers, bottom first: another glyph, and its palette entry (null for the text's own color). */
    class ColorLayer(val glyph: Int, val entry: Int?)

    /** Each colored glyph's layers, from the COLR table (version 0). */
    val colorLayers: Map<Int, List<ColorLayer>> by lazy {
        val colr = tables["COLR"]?.let(::Bytes) ?: return@lazy emptyMap()
        val baseCount = colr.u16(2)
        val baseOffset = colr.u32(4)
        val layerOffset = colr.u32(8)
        (0 until baseCount).associate { index ->
            val record = baseOffset + 6 * index
            val first = colr.u16(record + 2)
            val count = colr.u16(record + 4)
            colr.u16(record) to (0 until count).map { layer ->
                val at = layerOffset + 4 * (first + layer)
                val entry = colr.u16(at + 2)
                ColorLayer(colr.u16(at), if (entry == 0xFFFF) null else entry)
            }
        }
    }

    /** The CPAL palettes, each a list of colors as 0xRRGGBB. */
    val palettes: List<IntArray> by lazy {
        val cpal = tables["CPAL"]?.let(::Bytes) ?: return@lazy emptyList()
        val entries = cpal.u16(2)
        val count = cpal.u16(4)
        val records = cpal.u32(8)
        (0 until count).map { palette ->
            val first = cpal.u16(12 + 2 * palette)
            IntArray(entries) { entry ->
                val record = records + 4 * (first + entry)
                // BGRA records.
                (cpal.u8(record + 2) shl 16) or (cpal.u8(record + 1) shl 8) or cpal.u8(record)
            }
        }
    }

    // MARK: - Reading the tables

    private fun readCmap(cmap: Bytes): Map<Int, Int> {
        val map = HashMap<Int, Int>()
        val count = cmap.u16(2)
        // Prefer the full Unicode subtable (format 12), then the BMP one (format 4).
        val subtables = (0 until count).map { cmap.u32(4 + 8 * it + 4) }.distinct()
        val best = subtables.sortedByDescending { if (cmap.u16(it) == 12) 2 else if (cmap.u16(it) == 4) 1 else 0 }
        for (offset in best) {
            when (cmap.u16(offset)) {
                12 -> {
                    val groups = cmap.u32(offset + 12)
                    for (g in 0 until groups) {
                        val group = offset + 16 + 12 * g
                        val start = cmap.u32(group)
                        val end = cmap.u32(group + 4)
                        val glyph = cmap.u32(group + 8)
                        for (code in start..end) map.putIfAbsent(code, glyph + (code - start))
                    }
                }
                4 -> {
                    val segments = cmap.u16(offset + 6) / 2
                    val ends = offset + 14
                    val starts = ends + 2 * segments + 2
                    val deltas = starts + 2 * segments
                    val rangeOffsets = deltas + 2 * segments
                    for (s in 0 until segments) {
                        val end = cmap.u16(ends + 2 * s)
                        val start = cmap.u16(starts + 2 * s)
                        val delta = cmap.s16(deltas + 2 * s)
                        val rangeOffset = cmap.u16(rangeOffsets + 2 * s)
                        if (start == 0xFFFF) continue
                        for (code in start..end) {
                            val glyph = if (rangeOffset == 0) {
                                (code + delta) and 0xFFFF
                            } else {
                                val at = rangeOffsets + 2 * s + rangeOffset + 2 * (code - start)
                                cmap.u16(at).let { if (it == 0) 0 else (it + delta) and 0xFFFF }
                            }
                            if (glyph != 0) map.putIfAbsent(code, glyph)
                        }
                    }
                }
            }
        }
        return map
    }

    /** The kerning feature's pair adjustments (GPOS lookup type 2, x-advances only), for every script. */
    private fun readKerning(gpos: Bytes): Map<Long, Pair<Int, Int>> {
        val pairs = HashMap<Long, Pair<Int, Int>>()
        val featureList = gpos.u16(6)
        val lookupList = gpos.u16(8)
        val lookups = sortedSetOf<Int>()
        for (f in 0 until gpos.u16(featureList)) {
            val record = featureList + 2 + 6 * f
            val tag = String(gpos.data, record, 4, Charsets.ISO_8859_1)
            if (tag != "kern") continue
            val feature = featureList + gpos.u16(record + 4)
            for (i in 0 until gpos.u16(feature + 2)) lookups += gpos.u16(feature + 4 + 2 * i)
        }
        for (index in lookups) {
            val lookup = lookupList + gpos.u16(lookupList + 2 + 2 * index)
            val type = gpos.u16(lookup)
            require(type == 2) { "Unsupported GPOS lookup type $type in the kerning feature" }
            for (s in 0 until gpos.u16(lookup + 4)) {
                readPairPos(gpos, lookup + gpos.u16(lookup + 6 + 2 * s), pairs)
            }
        }
        return pairs
    }

    private fun readPairPos(gpos: Bytes, subtable: Int, pairs: MutableMap<Long, Pair<Int, Int>>) {
        val format = gpos.u16(subtable)
        val coverage = readCoverage(gpos, subtable + gpos.u16(subtable + 2))
        val format1 = gpos.u16(subtable + 4)
        val format2 = gpos.u16(subtable + 6)
        // Only x-advances: the page fonts kern nothing else.
        require(format1 and X_ADVANCE.inv() == 0 && format2 and X_ADVANCE.inv() == 0) {
            "Unsupported pair adjustment value formats ($format1, $format2)"
        }
        val size1 = Integer.bitCount(format1) * 2
        val size2 = Integer.bitCount(format2) * 2
        fun values(record: Int) = (if (format1 != 0) gpos.s16(record) else 0) to (if (format2 != 0) gpos.s16(record + size1) else 0)
        when (format) {
            1 -> for ((index, first) in coverage.withIndex()) {
                val set = subtable + gpos.u16(subtable + 10 + 2 * index)
                for (p in 0 until gpos.u16(set)) {
                    val record = set + 2 + p * (2 + size1 + size2)
                    pairs.putIfAbsent((first.toLong() shl 32) or gpos.u16(record).toLong(), values(record + 2))
                }
            }
            2 -> {
                val classes1 = readClassDef(gpos, subtable + gpos.u16(subtable + 8))
                val classes2 = readClassDef(gpos, subtable + gpos.u16(subtable + 10))
                val count2 = gpos.u16(subtable + 14)
                for (first in coverage) {
                    val class1 = classes1[first] ?: 0
                    for (second in 0 until glyphCount) {
                        val class2 = classes2[second] ?: 0
                        val adjustment = values(subtable + 16 + (class1 * count2 + class2) * (size1 + size2))
                        if (adjustment != NO_KERNING) pairs.putIfAbsent((first.toLong() shl 32) or second.toLong(), adjustment)
                    }
                }
            }
            else -> error("Unsupported pair adjustment format $format")
        }
    }

    private fun readCoverage(table: Bytes, offset: Int): List<Int> = when (table.u16(offset)) {
        1 -> List(table.u16(offset + 2)) { table.u16(offset + 4 + 2 * it) }
        2 -> (0 until table.u16(offset + 2)).flatMap { r ->
            val record = offset + 4 + 6 * r
            (table.u16(record)..table.u16(record + 2)).toList()
        }
        else -> emptyList()
    }

    private fun readClassDef(table: Bytes, offset: Int): Map<Int, Int> = when (table.u16(offset)) {
        1 -> {
            val start = table.u16(offset + 2)
            (0 until table.u16(offset + 4)).associate { start + it to table.u16(offset + 6 + 2 * it) }
        }
        2 -> buildMap {
            for (r in 0 until table.u16(offset + 2)) {
                val record = offset + 4 + 6 * r
                for (glyph in table.u16(record)..table.u16(record + 2)) put(glyph, table.u16(record + 4))
            }
        }
        else -> emptyMap()
    }
}

/** An affine transform of font units: x' = a·x + c·y + tx, y' = b·x + d·y + ty. */
class Transform(val a: Float, val b: Float, val c: Float, val d: Float, val tx: Float, val ty: Float) {
    fun apply(x: Float, y: Float): Pair<Float, Float> = (a * x + c * y + tx) to (b * x + d * y + ty)

    companion object {
        val IDENTITY = Transform(1f, 0f, 0f, 1f, 0f, 0f)
    }
}
