package com.azzamalrashed.aqra.quran

import kotlinx.serialization.json.Json

/** A word on a Mushaf page: its glyph in the page font, and whether it's an ayah-end marker. */
data class MushafWord(
    val glyph: String,
    val isAyahEnd: Boolean,
    /** The ayah it belongs to, numbered 0 until 6236 in Quran order. */
    val ayah: Int = 0,
    /** The topic section its ayah belongs to, numbered in Quran order. */
    val topic: Int? = null,
)

/** One line of a Mushaf page, as laid out in the 1441H Madinah print. */
data class MushafLine(val number: Int, val kind: Kind) {
    sealed interface Kind {
        data class SurahName(val surah: Int) : Kind
        data object Basmala : Kind
        /** The line's words in reading order. */
        data class Ayah(val words: List<MushafWord>, val centered: Boolean) : Kind
    }
}

data class MushafPage(
    val number: Int,
    val lines: List<MushafLine>,
    /** The page's ayat in the official Imla'i (plain) text, each followed by its number, for TalkBack. */
    val spokenAyat: List<String>,
    /** The ayah each of [spokenAyat] reads, by its number in the Quran. */
    val spokenAyahs: List<Int> = emptyList(),
    /** Every ayah that appears on the page, including one that starts or ends on it. */
    val ayahs: IntRange,
    /** The surah the page starts in, and its juz'. */
    val surah: Int,
    val juz: Int,
)

/** Where the bundled Quran data (`shared/quran`) is read from: the app's assets, or the repository in tests. */
interface QuranFiles {
    fun exists(path: String): Boolean
    fun read(path: String): ByteArray
    /** Runs a query on a bundled SQLite file, calling `row` for each result row. */
    fun query(path: String, sql: String, row: (QueryRow) -> Unit)
}

interface QueryRow {
    fun int(column: Int): Int
    fun string(column: Int): String
}

/**
 * Reads the bundled Quran data and builds the Mushaf's pages.
 *
 * Pages and words come from the QUL "KFGQPC V4 layout (1441H print)" and its glyphs, which match the King Fahd
 * Complex's official data line for line; surah names, juz' and the basmala come from that official data.
 */
class MushafStore(files: QuranFiles) {
    companion object {
        const val PAGE_COUNT = 604
        const val AYAH_COUNT = 6236

        /** The page's own QCF V4 font (1441H print), whose glyphs are that page's words, with tajweed colors. */
        fun pageFontPath(page: Int) = "qcf4/p$page.woff2"

        private val json = Json { ignoreUnknownKeys = true }

        /** The official data's ayat, in order. */
        internal fun parseOfficial(bytes: ByteArray): List<OfficialAyah> {
            val scanner = JsonScanner(bytes)
            val ayat = ArrayList<OfficialAyah>(AYAH_COUNT)
            scanner.beginArray()
            while (scanner.hasNext()) {
                var surah = 0; var name = ""; var number = 0; var page = 0; var juz = 0; var text = ""; var plain = ""
                scanner.beginObject()
                while (scanner.hasNext()) {
                    when (scanner.nextName()) {
                        "sura_no" -> surah = scanner.nextInt()
                        "sura_name_ar" -> name = scanner.nextString()
                        "aya_no" -> number = scanner.nextInt()
                        "page" -> page = scanner.nextInt()
                        "jozz" -> juz = scanner.nextInt()
                        "aya_text" -> text = scanner.nextString()
                        "aya_text_emlaey" -> plain = scanner.nextString()
                        else -> scanner.skipValue()
                    }
                }
                scanner.endObject()
                ayat += OfficialAyah(surah, name, number, page, juz, text, plain)
            }
            scanner.endArray()
            return ayat
        }

        /** QUL's glyph data: an object of words by their location. */
        internal fun parseWords(bytes: ByteArray): List<Word> {
            val scanner = JsonScanner(bytes)
            val words = ArrayList<Word>(84_000)
            scanner.beginObject()
            while (scanner.hasNext()) {
                scanner.nextName()
                var id = 0; var surah = 0; var ayah = 0; var word = 0; var text = ""
                scanner.beginObject()
                while (scanner.hasNext()) {
                    when (scanner.nextName()) {
                        "id" -> id = scanner.nextInt()
                        "surah" -> surah = scanner.nextInt()
                        "ayah" -> ayah = scanner.nextInt()
                        "word" -> word = scanner.nextInt()
                        "text" -> text = scanner.nextString()
                        else -> scanner.skipValue()
                    }
                }
                scanner.endObject()
                words += Word(id, surah, ayah, word, text)
            }
            scanner.endObject()
            return words
        }
    }

    sealed class LoadError(message: String) : Exception(message) {
        class MissingResource(path: String) : LoadError("Missing Quran data file: $path")
        class MissingPageFonts(val found: Int) :
            LoadError("Only $found of 604 Mushaf page fonts are in the app. Run scripts/fetch-mushaf-fonts.sh, then rebuild.")
    }

    /** One ayah of the Complex's official data, with the fields the Mushaf reads. */
    class OfficialAyah(
        val sura_no: Int,
        val sura_name_ar: String,
        val aya_no: Int,
        val page: Int,
        val jozz: Int,
        val aya_text: String,
        val aya_text_emlaey: String,
    )

    /** One word of QUL's glyph data: its id in the layout, where it is in the Quran, and its glyph. */
    class Word(val id: Int, val surah: Int, val ayah: Int, val word: Int, val text: String)

    /** Official Arabic surah names, by surah number. */
    val surahNames: Map<Int, String>
    /** Each surah's header glyph in the surah header font, by surah number. */
    val surahHeaders: Map<Int, String>
    /** The page each surah starts on. */
    val surahStartPages: Map<Int, Int>
    /** The page each juz' starts on, from the official data. */
    val juzStartPages: Map<Int, Int>
    /** Each surah's ayat and each juz's ayat, numbered 0 until 6236 in Quran order. */
    val surahAyahs: Map<Int, IntRange>
    val juzAyahs: Map<Int, IntRange>
    /** «بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ» in the official Hafs Smart encoding: al-Fatiha 1:1 without its number. */
    val basmala: String
    /**
     * Each ayah's text in the official Hafs Smart encoding, with its number marker, exactly as published: drawn in the
     * Complex's Hafs Smart font where an ayah stands on its own (the stage tests).
     */
    val ayahTexts: List<String>
    /** Each ayah's plain (Imla'i) text from the official data, for TalkBack. */
    val ayahPlainTexts: List<String>
    /**
     * How long each ayah is, in lines of the 15-line page: each line it shares counts by its share of the line's words.
     * The personal plan measures portions with it.
     */
    val ayahLines: DoubleArray

    private val pages: List<MushafPage>

    init {
        fun read(path: String): ByteArray {
            if (!files.exists(path)) throw LoadError.MissingResource(path)
            return files.read(path)
        }

        // The 604 page fonts aren't in git; catch a build made without them before any page renders.
        val pageFonts = (1..PAGE_COUNT).count { files.exists(pageFontPath(it)) }
        if (pageFonts != PAGE_COUNT) throw LoadError.MissingPageFonts(pageFonts)

        // The two large files are read at once, each on its own thread.
        val officialBytes = read("kfgqpc/hafs_smart_v8.json")
        val wordBytes = read("qul/qpc-v4.json")
        var parsedWords: List<Word>? = null
        var wordsError: Throwable? = null
        val wordsThread = Thread {
            try {
                parsedWords = parseWords(wordBytes)
            } catch (error: Throwable) {
                wordsError = error
            }
        }.apply { start() }

        // Official data: surah names, juz' per page, the basmala, and plain text for TalkBack.
        val official = parseOfficial(officialBytes)
        // The official data lists the ayat in Quran order, so an ayah's position there is its number.
        val indexOfAyah = HashMap<String, Int>(AYAH_COUNT * 2)
        val surahRanges = HashMap<Int, IntRange>()
        val juzRanges = HashMap<Int, IntRange>()
        official.forEachIndexed { index, ayah ->
            indexOfAyah["${ayah.sura_no}:${ayah.aya_no}"] = index
            surahRanges[ayah.sura_no] = (surahRanges[ayah.sura_no]?.first ?: index)..index
            juzRanges[ayah.jozz] = (juzRanges[ayah.jozz]?.first ?: index)..index
        }
        surahAyahs = surahRanges
        juzAyahs = juzRanges
        val names = HashMap<Int, String>()
        val firstAyahOnPage = HashMap<Int, OfficialAyah>()
        val juzStarts = HashMap<Int, Int>()
        val spoken = Array(PAGE_COUNT + 1) { ArrayList<String>() }
        val spokenAyahs = Array(PAGE_COUNT + 1) { ArrayList<Int>() }
        // The official data lists the ayat in Quran order, so an ayah's position there is its number.
        for ((index, ayah) in official.withIndex()) {
            if (ayah.page in 1..PAGE_COUNT) {
                spoken[ayah.page] += "${ayah.aya_text_emlaey} (${ayah.aya_no})"
                spokenAyahs[ayah.page] += index
            }
            names.putIfAbsent(ayah.sura_no, ayah.sura_name_ar)
            firstAyahOnPage.putIfAbsent(ayah.page, ayah)
            juzStarts.putIfAbsent(ayah.jozz, ayah.page)
        }
        surahNames = names
        juzStartPages = juzStarts

        // Surah header glyphs: "surah-N" → glyph (with a trailing space in the source file).
        val headerMap = json.decodeFromString<Map<String, String>>(read("qul/surah-header-ligatures.json").decodeToString())
        surahHeaders = headerMap.mapNotNull { (key, value) ->
            key.removePrefix("surah-").toIntOrNull()?.let { it to value.trim(' ') }
        }.toMap()
        val fatiha = official.firstOrNull { it.sura_no == 1 && it.aya_no == 1 }?.aya_text.orEmpty()
        basmala = fatiha.split(" ").dropLast(1).joinToString(" ")
        ayahTexts = official.map { it.aya_text }
        ayahPlainTexts = official.map { it.aya_text_emlaey }

        // QUL glyphs: word id → glyph. The last word of each ayah is its ayah-end marker.
        wordsThread.join()
        wordsError?.let { throw it }
        val words = parsedWords.orEmpty()
        val glyph = arrayOfNulls<String>(words.size + 1)
        val ayahOfWord = arrayOfNulls<String>(words.size + 1)
        val lastWordOfAyah = HashMap<String, Pair<Int, Int>>()
        for (word in words) {
            if (word.id !in glyph.indices) continue
            glyph[word.id] = word.text
            val key = "${word.surah}:${word.ayah}"
            ayahOfWord[word.id] = key
            if (word.word > (lastWordOfAyah[key]?.first ?: 0)) lastWordOfAyah[key] = word.word to word.id
        }
        val ayahEnds = lastWordOfAyah.values.mapTo(HashSet()) { it.second }

        // Topic sections (QUL "Ayah theme", a provisional stand-in): ayah ranges. The source lists every section
        // twice (DISTINCT keeps one of each) and leaves 36 ayat in four gaps outside any section; each gap becomes a
        // section of its own, so every ayah is colored without moving a boundary the source draws.
        val sectionOfAyah = HashMap<String, String>()
        files.query("qul/ayah-themes.db",
            "SELECT DISTINCT surah_number, ayah_from, ayah_to FROM themes ORDER BY surah_number, ayah_from") { row ->
            val surah = row.int(0)
            val from = row.int(1)
            for (ayah in from..maxOf(row.int(2), from)) sectionOfAyah["$surah:$ayah"] = "$surah:$from"
        }
        // Numbered in Quran order, so neighboring sections never share a color.
        val topicOfAyah = HashMap<String, Int>(AYAH_COUNT * 2)
        var topic = -1
        var previousSection: String? = null
        for (ayah in official) {
            val key = "${ayah.sura_no}:${ayah.aya_no}"
            val section = sectionOfAyah[key] ?: "gap in ${ayah.sura_no}"
            if (section != previousSection) topic += 1
            previousSection = section
            topicOfAyah[key] = topic
        }

        // QUL layout: 15 lines per page.
        val linesByPage = Array(PAGE_COUNT + 1) { ArrayList<MushafLine>() }
        files.query("qul/qpc-v4-tajweed-15-lines.db",
            "SELECT page_number, line_number, line_type, is_centered, first_word_id, last_word_id, surah_number " +
                "FROM pages ORDER BY page_number, line_number") { row ->
            val page = row.int(0)
            val kind = when (row.string(2)) {
                "surah_name" -> MushafLine.Kind.SurahName(row.int(6))
                "basmallah" -> MushafLine.Kind.Basmala
                else -> MushafLine.Kind.Ayah(
                    words = (row.int(4)..row.int(5)).map { id ->
                        val key = ayahOfWord[id]
                        MushafWord(glyph[id].orEmpty(), id in ayahEnds, indexOfAyah[key] ?: 0, topicOfAyah[key])
                    },
                    centered = row.int(3) != 0,
                )
            }
            if (page in 1..PAGE_COUNT) linesByPage[page] += MushafLine(row.int(1), kind)
        }

        // Each ayah's share of every line it's on, by words.
        val lengths = DoubleArray(AYAH_COUNT)
        for (lines in linesByPage) {
            for (line in lines) {
                val words = (line.kind as? MushafLine.Kind.Ayah)?.words ?: continue
                if (words.isEmpty()) continue
                val share = 1.0 / words.size
                for (word in words) if (word.ayah in 0 until AYAH_COUNT) lengths[word.ayah] += share
            }
        }
        ayahLines = lengths

        val surahStarts = HashMap<Int, Int>()
        for (page in 1..PAGE_COUNT) {
            for (line in linesByPage[page]) {
                (line.kind as? MushafLine.Kind.SurahName)?.let { surahStarts.putIfAbsent(it.surah, page) }
            }
        }
        surahStartPages = surahStarts

        pages = (1..PAGE_COUNT).map { number ->
            val first = firstAyahOnPage[number]
            val ayahs = linesByPage[number].flatMap { line -> (line.kind as? MushafLine.Kind.Ayah)?.words?.map { it.ayah }.orEmpty() }
            MushafPage(
                number = number, lines = linesByPage[number], spokenAyat = spoken[number], spokenAyahs = spokenAyahs[number],
                ayahs = (ayahs.minOrNull() ?: 0)..(ayahs.maxOrNull() ?: 0),
                surah = first?.sura_no ?: 1, juz = first?.jozz ?: 1,
            )
        }
    }

    /** The surah being read on a page: the last surah that starts on or before it. */
    fun surahOf(page: Int): Int =
        surahStartPages.filter { it.value <= page }.maxWithOrNull(compareBy({ it.value }, { it.key }))?.key ?: 1

    /** The juz' a page belongs to: the last juz' that starts on or before it. */
    fun juzOf(page: Int): Int =
        juzStartPages.filter { it.value <= page }.maxWithOrNull(compareBy({ it.value }, { it.key }))?.key ?: 1

    fun page(number: Int): MushafPage = pages[number.coerceIn(1, PAGE_COUNT) - 1]

    /** An ayah's surah and its number in the surah, from its number in the Quran (0 until 6236). */
    fun reference(ayah: Int): Pair<Int, Int> {
        val index = ayah.coerceIn(0, AYAH_COUNT - 1)
        val (surah, range) = surahAyahs.entries.firstOrNull { index in it.value }?.toPair() ?: return 1 to 1
        return surah to index - range.first + 1
    }

    /** The length of some ayat in lines of the page. */
    fun lines(ayahs: Iterable<Int>): Double = ayahs.sumOf { ayahLines[it.coerceIn(0, AYAH_COUNT - 1)] }

    /** The surah an ayah belongs to. */
    fun surahOfAyah(ayah: Int): Int = reference(ayah).first

    /** The juz' an ayah belongs to. */
    fun juzOfAyah(ayah: Int): Int = juzAyahs.entries.firstOrNull { ayah in it.value }?.key ?: 1

    /** The page an ayah starts on: the first page that holds any of it. */
    fun pageOfAyah(ayah: Int): Int {
        var low = 1
        var high = PAGE_COUNT
        while (low < high) {
            val middle = (low + high) / 2
            if (pages[middle - 1].ayahs.last >= ayah) high = middle else low = middle + 1
        }
        return low
    }
}
