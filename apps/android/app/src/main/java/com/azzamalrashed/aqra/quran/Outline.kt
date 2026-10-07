package com.azzamalrashed.aqra.quran

import kotlin.math.max
import kotlin.math.min

/**
 * A glyph's outline as path commands, in font units with y up: move, line, quadratic curve and close, the way a
 * TrueType outline is drawn. Kept free of Android types so the tests can measure it.
 */
class Outline private constructor(
    /** One verb per command: [MOVE], [LINE], [QUAD] or [CLOSE]. */
    val verbs: ByteArray,
    /** The commands' points, two floats each: one for move and line, two (control, end) for a curve. */
    val points: FloatArray,
) {
    companion object {
        const val MOVE: Byte = 0
        const val LINE: Byte = 1
        const val QUAD: Byte = 2
        const val CLOSE: Byte = 3
        val EMPTY = Outline(ByteArray(0), FloatArray(0))
    }

    val isEmpty: Boolean get() = verbs.isEmpty()

    /** Calls the right function for each command, in order. */
    inline fun forEach(
        move: (Float, Float) -> Unit,
        line: (Float, Float) -> Unit,
        quad: (Float, Float, Float, Float) -> Unit,
        close: () -> Unit,
    ) {
        var p = 0
        for (verb in verbs) {
            when (verb) {
                MOVE -> { move(points[p], points[p + 1]); p += 2 }
                LINE -> { line(points[p], points[p + 1]); p += 2 }
                QUAD -> { quad(points[p], points[p + 1], points[p + 2], points[p + 3]); p += 4 }
                else -> close()
            }
        }
    }

    /** The tight box around the ink, curves' extremes included: (minX, minY, maxX, maxY), or null when empty. */
    fun bounds(): FloatArray? {
        if (isEmpty) return null
        var minX = Float.MAX_VALUE
        var minY = Float.MAX_VALUE
        var maxX = -Float.MAX_VALUE
        var maxY = -Float.MAX_VALUE
        fun include(x: Float, y: Float) {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
        var lastX = 0f
        var lastY = 0f
        forEach(
            move = { x, y -> include(x, y); lastX = x; lastY = y },
            line = { x, y -> include(x, y); lastX = x; lastY = y },
            quad = { cx, cy, x, y ->
                include(x, y)
                // Where the curve turns along each axis, if it does between its ends.
                quadExtreme(lastX, cx, x)?.let { t -> include(quadAt(lastX, cx, x, t), quadAt(lastY, cy, y, t)) }
                quadExtreme(lastY, cy, y)?.let { t -> include(quadAt(lastX, cx, x, t), quadAt(lastY, cy, y, t)) }
                lastX = x; lastY = y
            },
            close = {},
        )
        return floatArrayOf(minX, minY, maxX, maxY)
    }

    /** The signed area enclosed (positive counter-clockwise), counting each closed contour. */
    fun area(): Double {
        var area = 0.0
        var startX = 0.0
        var startY = 0.0
        var lastX = 0.0
        var lastY = 0.0
        fun cross(ax: Double, ay: Double, bx: Double, by: Double) = ax * by - ay * bx
        forEach(
            move = { x, y ->
                area += cross(lastX, lastY, startX, startY) / 2
                startX = x.toDouble(); startY = y.toDouble(); lastX = startX; lastY = startY
            },
            line = { x, y ->
                area += cross(lastX, lastY, x.toDouble(), y.toDouble()) / 2
                lastX = x.toDouble(); lastY = y.toDouble()
            },
            quad = { cx, cy, x, y ->
                val c = cx.toDouble() to cy.toDouble()
                val e = x.toDouble() to y.toDouble()
                area += (cross(lastX, lastY, e.first, e.second) / 3 +
                    2.0 / 3 * (cross(lastX, lastY, c.first, c.second) + cross(c.first, c.second, e.first, e.second))) / 2
                lastX = e.first; lastY = e.second
            },
            close = {
                area += cross(lastX, lastY, startX, startY) / 2
                lastX = startX; lastY = startY
            },
        )
        return area
    }

    /** The outline moved by (dx, dy), for laying glyphs side by side. */
    fun offset(dx: Float, dy: Float): Outline {
        if (dx == 0f && dy == 0f) return this
        return Outline(verbs, FloatArray(points.size) { if (it % 2 == 0) points[it] + dx else points[it] + dy })
    }

    private fun quadExtreme(p0: Float, c: Float, p1: Float): Float? {
        val denominator = p0 - 2 * c + p1
        if (denominator == 0f) return null
        val t = (p0 - c) / denominator
        return if (t > 0f && t < 1f) t else null
    }

    private fun quadAt(p0: Float, c: Float, p1: Float, t: Float): Float {
        val u = 1 - t
        return u * u * p0 + 2 * u * t * c + t * t * p1
    }

    /** Builds an outline from TrueType contours and other outlines. */
    class Builder {
        private var verbs = ByteArray(64)
        private var points = FloatArray(128)
        private var verbCount = 0
        private var pointCount = 0

        private fun verb(verb: Byte) {
            if (verbCount == verbs.size) verbs = verbs.copyOf(verbs.size * 2)
            verbs[verbCount++] = verb
        }

        private fun point(x: Float, y: Float) {
            if (pointCount + 2 > points.size) points = points.copyOf(points.size * 2)
            points[pointCount++] = x
            points[pointCount++] = y
        }

        fun moveTo(x: Float, y: Float) { verb(MOVE); point(x, y) }
        fun lineTo(x: Float, y: Float) { verb(LINE); point(x, y) }
        fun quadTo(cx: Float, cy: Float, x: Float, y: Float) { verb(QUAD); point(cx, cy); point(x, y) }
        fun close() = verb(CLOSE)

        fun add(outline: Outline) {
            outline.forEach(::moveTo, ::lineTo, ::quadTo, ::close)
        }

        /**
         * A simple glyph's contours. Two off-curve points in a row imply an on-curve point halfway between them; a
         * contour starts at its first on-curve point (or halfway between its last and first points if it has none).
         */
        fun addContours(glyph: GlyphData.Simple, transform: Transform) {
            var start = 0
            for (end in glyph.ends) {
                val count = end - start + 1
                if (count > 0) addContour(glyph, start, count, transform)
                start = end + 1
            }
        }

        private fun addContour(glyph: GlyphData.Simple, first: Int, count: Int, transform: Transform) {
            fun x(i: Int) = glyph.xs[first + i].toFloat()
            fun y(i: Int) = glyph.ys[first + i].toFloat()
            fun on(i: Int) = glyph.onCurve[first + i]
            fun emitMove(px: Float, py: Float) = transform.apply(px, py).let { moveTo(it.first, it.second) }
            fun emitLine(px: Float, py: Float) = transform.apply(px, py).let { lineTo(it.first, it.second) }
            fun emitQuad(cx: Float, cy: Float, px: Float, py: Float) {
                val c = transform.apply(cx, cy)
                val p = transform.apply(px, py)
                quadTo(c.first, c.second, p.first, p.second)
            }

            val startX: Float
            val startY: Float
            val order: IntRange
            when {
                on(0) -> { startX = x(0); startY = y(0); order = 1 until count }
                on(count - 1) -> { startX = x(count - 1); startY = y(count - 1); order = 0 until count - 1 }
                else -> {
                    // Halfway between the last and first points, in whole font units (truncated), as CoreText does.
                    startX = ((glyph.xs[first + count - 1] + glyph.xs[first]) / 2).toFloat()
                    startY = ((glyph.ys[first + count - 1] + glyph.ys[first]) / 2).toFloat()
                    order = 0 until count
                }
            }
            emitMove(startX, startY)
            var hasControl = false
            var controlX = 0f
            var controlY = 0f
            for (i in order) {
                if (on(i)) {
                    if (hasControl) emitQuad(controlX, controlY, x(i), y(i)) else emitLine(x(i), y(i))
                    hasControl = false
                } else {
                    if (hasControl) emitQuad(controlX, controlY, (controlX + x(i)) / 2, (controlY + y(i)) / 2)
                    controlX = x(i); controlY = y(i); hasControl = true
                }
            }
            if (hasControl) emitQuad(controlX, controlY, startX, startY) else emitLine(startX, startY)
            close()
        }

        fun build(): Outline =
            if (verbCount == 0) EMPTY else Outline(verbs.copyOf(verbCount), points.copyOf(pointCount))
    }
}
