package com.azzamalrashed.aqra.quran

/**
 * A small streaming JSON reader over UTF-8 bytes, for the two large Quran data files: reading them this way, without
 * building a tree of every value first, keeps the Mushaf's loading quick on phones. Strict about the JSON it accepts;
 * `JsonScannerTest` checks it reads both files exactly as kotlinx.serialization does.
 */
class JsonScanner(private val bytes: ByteArray) {
    private var position = 0
    /** Field names repeat for every entry; each one is made into a String once. */
    private val names = HashMap<Int, Array<Any>>()

    private fun skipWhitespace() {
        while (position < bytes.size) {
            when (bytes[position].toInt()) {
                0x20, 0x09, 0x0A, 0x0D -> position++
                else -> return
            }
        }
    }

    private fun peek(): Int {
        skipWhitespace()
        require(position < bytes.size) { "Unexpected end of JSON" }
        return bytes[position].toInt() and 0xFF
    }

    private fun expect(byte: Char) {
        require(peek() == byte.code) { "Expected '$byte' at $position" }
        position++
    }

    fun beginObject() = expect('{')
    fun endObject() = expect('}')
    fun beginArray() = expect('[')
    fun endArray() = expect(']')

    /** Whether the object or array being read has another member; consumes the comma before it. */
    fun hasNext(): Boolean {
        val next = peek()
        if (next == '}'.code || next == ']'.code) return false
        if (next == ','.code) {
            position++
            return true
        }
        return true
    }

    /** The next member's name, and the colon after it. */
    fun nextName(): String {
        require(peek() == '"'.code) { "Expected a name at $position" }
        val start = position + 1
        var end = start
        var hash = 0
        var plain = true
        while (true) {
            val byte = bytes[end].toInt()
            if (byte == '"'.code) break
            if (byte == '\\'.code) plain = false
            hash = 31 * hash + byte
            end++
        }
        val name = if (plain && end - start <= 32) {
            val cached = names[hash]
            if (cached != null && sameBytes(cached[1] as ByteArray, start, end)) {
                position = end + 1
                cached[0] as String
            } else {
                val made = String(bytes, start, end - start, Charsets.UTF_8)
                names[hash] = arrayOf(made, bytes.copyOfRange(start, end))
                position = end + 1
                made
            }
        } else {
            nextString()
        }
        expect(':')
        return name
    }

    private fun sameBytes(other: ByteArray, start: Int, end: Int): Boolean {
        if (other.size != end - start) return false
        for (i in other.indices) if (other[i] != bytes[start + i]) return false
        return true
    }

    fun nextString(): String {
        require(peek() == '"'.code) { "Expected a string at $position" }
        val start = position + 1
        var end = start
        while (true) {
            val byte = bytes[end].toInt()
            if (byte == '"'.code) {
                position = end + 1
                return String(bytes, start, end - start, Charsets.UTF_8)
            }
            if (byte == '\\'.code) break
            end++
        }
        // With escapes: decode it piece by piece.
        val out = StringBuilder(String(bytes, start, end - start, Charsets.UTF_8))
        position = end
        while (true) {
            val byte = bytes[position].toInt()
            when (byte) {
                '"'.code -> {
                    position++
                    return out.toString()
                }
                '\\'.code -> {
                    val escape = bytes[position + 1].toInt().toChar()
                    position += 2
                    when (escape) {
                        '"' -> out.append('"')
                        '\\' -> out.append('\\')
                        '/' -> out.append('/')
                        'b' -> out.append('\b')
                        'f' -> out.append('\u000C')
                        'n' -> out.append('\n')
                        'r' -> out.append('\r')
                        't' -> out.append('\t')
                        'u' -> {
                            out.append(String(bytes, position, 4, Charsets.US_ASCII).toInt(16).toChar())
                            position += 4
                        }
                        else -> error("Bad escape \\$escape at $position")
                    }
                }
                else -> {
                    // A run of plain bytes up to the next quote or escape.
                    var runEnd = position
                    while (bytes[runEnd].toInt() != '"'.code && bytes[runEnd].toInt() != '\\'.code) runEnd++
                    out.append(String(bytes, position, runEnd - position, Charsets.UTF_8))
                    position = runEnd
                }
            }
        }
    }

    /** A whole number, written as a number or as a string of digits ("12"). */
    fun nextInt(): Int {
        val quoted = peek() == '"'.code
        if (quoted) position++
        var negative = false
        if (bytes[position].toInt() == '-'.code) {
            negative = true
            position++
        }
        var value = 0
        var digits = 0
        while (position < bytes.size) {
            val byte = bytes[position].toInt()
            if (byte < '0'.code || byte > '9'.code) break
            value = value * 10 + (byte - '0'.code)
            digits++
            position++
        }
        require(digits > 0) { "Expected a number at $position" }
        if (quoted) {
            require(bytes[position].toInt() == '"'.code) { "Expected a whole number at $position" }
            position++
        } else {
            require(position >= bytes.size || bytes[position].toInt().toChar() !in ".eE") { "Expected a whole number at $position" }
        }
        return if (negative) -value else value
    }

    /** Skips a value of any kind. */
    fun skipValue() {
        when (peek()) {
            '"'.code -> nextString()
            '{'.code -> {
                beginObject()
                while (hasNext()) {
                    nextName()
                    skipValue()
                }
                endObject()
            }
            '['.code -> {
                beginArray()
                while (hasNext()) skipValue()
                endArray()
            }
            else -> {
                // A number, true, false or null.
                while (position < bytes.size) {
                    val byte = bytes[position].toInt().toChar()
                    if (byte == ',' || byte == '}' || byte == ']' || byte.isWhitespace()) break
                    position++
                }
            }
        }
    }
}
