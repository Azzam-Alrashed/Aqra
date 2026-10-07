import Foundation
import SQLite3

/// A word on a Mushaf page: its glyph in the page font, and whether it's an ayah-end marker.
struct MushafWord: Hashable {
    var glyph: String
    var isAyahEnd: Bool
    /// The ayah it belongs to, numbered 0..<6236 in Quran order.
    var ayah = 0
    /// The topic section its ayah belongs to, numbered in Quran order.
    var topic: Int? = nil
}

/// One line of a Mushaf page, as laid out in the 1441H Madinah print.
struct MushafLine: Hashable {
    enum Kind: Hashable {
        case surahName(surah: Int)
        case basmala
        /// The line's words in reading order.
        case ayah(words: [MushafWord], centered: Bool)
    }

    var number: Int
    var kind: Kind
}

struct MushafPage: Hashable {
    var number: Int
    var lines: [MushafLine]
    /// The page's ayat in the official Imla'i (plain) text, each followed by its number — for VoiceOver.
    var spokenAyat: [String] = []
    /// Every ayah that appears on the page, including one that starts or ends on it.
    var ayahs: ClosedRange<Int> = 0...0
    /// The surah the page starts in, and its juz'.
    var surah: Int
    var juz: Int
}

/// Reads the bundled Quran data (`shared/quran`) and builds Mushaf pages.
///
/// Pages and words come from the QUL "KFGQPC V4 layout (1441H print)" and its glyphs, which match the
/// King Fahd Complex's official data line for line; surah names, juz' and the basmala come from that official data.
final class MushafStore: Sendable {
    static let pageCount = 604
    static let ayahCount = 6236

    enum LoadError: Error, CustomStringConvertible {
        case missingResource(String)
        case missingPageFonts(found: Int)
        case database(String)

        var description: String {
            switch self {
            case .missingResource(let path): "Missing Quran data file: \(path)"
            case .missingPageFonts(let found):
                "Only \(found) of 604 Mushaf page fonts are in the app. Run scripts/fetch-mushaf-fonts.sh, then rebuild."
            case .database(let step): "Couldn't read the Mushaf layout (\(step))."
            }
        }
    }

    /// Official Arabic surah names, indexed by surah number.
    let surahNames: [Int: String]
    /// Each surah's header glyph in the surah header font, indexed by surah number.
    let surahHeaders: [Int: String]
    /// The page each surah starts on, in surah order.
    let surahStartPages: [Int: Int]
    /// The page each juz' starts on, by juz' number, from the official data.
    let juzStartPages: [Int: Int]
    /// Each surah's ayat and each juz's ayat, numbered 0..<6236 in Quran order.
    let surahAyahs: [Int: ClosedRange<Int>]
    let juzAyahs: [Int: ClosedRange<Int>]
    /// «بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ» in the official Hafs Smart encoding — the words of al-Fatiha 1:1
    /// without its ayah-number marker.
    let basmala: String

    private let pages: [MushafPage]

    /// Where the Quran data lives in the bundle.
    static func resourceURL(_ path: String, in bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent("quran").appendingPathComponent(path)
    }

    init(bundle: Bundle = .main) throws {
        func url(_ path: String) throws -> URL {
            guard let url = Self.resourceURL(path, in: bundle), FileManager.default.fileExists(atPath: url.path) else {
                throw LoadError.missingResource(path)
            }
            return url
        }

        // The 604 page fonts aren't in git; catch a build made without them before any page renders.
        let pageFonts = (1...Self.pageCount).filter { page in
            Self.resourceURL(MushafFonts.pageFontPath(page), in: bundle)
                .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        }.count
        guard pageFonts == Self.pageCount else { throw LoadError.missingPageFonts(found: pageFonts) }

        // Official data: surah names, juz' per page, the basmala, and plain text for VoiceOver.
        struct OfficialAyah: Decodable {
            var sura_no: Int
            var sura_name_ar: String
            var aya_no: Int
            var page: Int
            var jozz: Int
            var aya_text: String
            var aya_text_emlaey: String
        }
        let official = try JSONDecoder().decode([OfficialAyah].self, from: Data(contentsOf: url("kfgqpc/hafs_smart_v8.json")))
        var names: [Int: String] = [:]
        var firstAyahOnPage: [Int: OfficialAyah] = [:]
        var juzStarts: [Int: Int] = [:]
        var spoken = [[String]](repeating: [], count: Self.pageCount + 1)
        // The official data lists the ayat in Quran order, so an ayah's position there is its number.
        var indexOfAyah: [String: Int] = [:]
        var surahRanges: [Int: ClosedRange<Int>] = [:], juzRanges: [Int: ClosedRange<Int>] = [:]
        for (index, ayah) in official.enumerated() {
            indexOfAyah["\(ayah.sura_no):\(ayah.aya_no)"] = index
            surahRanges[ayah.sura_no] = (surahRanges[ayah.sura_no]?.lowerBound ?? index)...index
            juzRanges[ayah.jozz] = (juzRanges[ayah.jozz]?.lowerBound ?? index)...index
        }
        surahAyahs = surahRanges
        juzAyahs = juzRanges
        for ayah in official {
            if (1...Self.pageCount).contains(ayah.page) {
                spoken[ayah.page].append("\(ayah.aya_text_emlaey) (\(ayah.aya_no))")
            }
            names[ayah.sura_no] = names[ayah.sura_no] ?? ayah.sura_name_ar
            firstAyahOnPage[ayah.page] = firstAyahOnPage[ayah.page] ?? ayah
            juzStarts[ayah.jozz] = juzStarts[ayah.jozz] ?? ayah.page
        }
        surahNames = names
        juzStartPages = juzStarts

        // Surah header glyphs: "surah-N" → glyph (with a trailing space in the source file).
        let headerMap = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url("qul/surah-header-ligatures.json")))
        var headers: [Int: String] = [:]
        for (key, value) in headerMap {
            if let number = Int(key.replacingOccurrences(of: "surah-", with: "")) {
                headers[number] = value.trimmingCharacters(in: .whitespaces)
            }
        }
        surahHeaders = headers
        let fatiha = official.first { $0.sura_no == 1 && $0.aya_no == 1 }?.aya_text ?? ""
        basmala = fatiha.split(separator: " ").dropLast().joined(separator: " ")

        // QUL glyphs: word id → glyph. The last word of each ayah is its ayah-end marker.
        struct Word: Decodable { var id: Int; var surah: String; var ayah: String; var word: String; var text: String }
        let words = try JSONDecoder().decode([String: Word].self, from: Data(contentsOf: url("qul/qpc-v4.json")))
        var glyph = [String](repeating: "", count: words.count + 1)
        var ayahOfWord = [String](repeating: "", count: words.count + 1)
        var lastWordOfAyah: [String: (position: Int, id: Int)] = [:]
        for word in words.values where word.id < glyph.count {
            glyph[word.id] = word.text
            let key = "\(word.surah):\(word.ayah)", position = Int(word.word) ?? 0
            ayahOfWord[word.id] = key
            if position > (lastWordOfAyah[key]?.position ?? 0) { lastWordOfAyah[key] = (position, word.id) }
        }
        let ayahEnds = Set(lastWordOfAyah.values.map(\.id))

        // Topic sections (QUL "Ayah theme", a provisional stand-in): ayah ranges. The source lists every section
        // twice (DISTINCT keeps one of each) and leaves 36 ayat in four gaps outside any section; each gap
        // becomes a section of its own, so every ayah is colored without moving a boundary the source draws.
        var sectionOfAyah: [String: String] = [:]
        try Self.query(url("qul/ayah-themes.db"),
                       "SELECT DISTINCT surah_number, ayah_from, ayah_to FROM themes ORDER BY surah_number, ayah_from") { row in
            let surah = Int(sqlite3_column_int(row, 0)), from = Int(sqlite3_column_int(row, 1))
            for ayah in from...max(Int(sqlite3_column_int(row, 2)), from) {
                sectionOfAyah["\(surah):\(ayah)"] = "\(surah):\(from)"
            }
        }
        // Numbered in Quran order, so neighboring sections never share a color.
        var topicOfAyah: [String: Int] = [:]
        var topic = -1, previousSection: String?
        for ayah in official {
            let key = "\(ayah.sura_no):\(ayah.aya_no)"
            let section = sectionOfAyah[key] ?? "gap in \(ayah.sura_no)"
            if section != previousSection { topic += 1 }
            previousSection = section
            topicOfAyah[key] = topic
        }

        // QUL layout: 15 lines per page.
        var linesByPage = [[MushafLine]](repeating: [], count: Self.pageCount + 1)
        let sql = "SELECT page_number, line_number, line_type, is_centered, first_word_id, last_word_id, surah_number FROM pages ORDER BY page_number, line_number"
        try Self.query(url("qul/qpc-v4-tajweed-15-lines.db"), sql) { statement in
            let page = Int(sqlite3_column_int(statement, 0))
            let number = Int(sqlite3_column_int(statement, 1))
            let type = String(cString: sqlite3_column_text(statement, 2))
            let kind: MushafLine.Kind
            switch type {
            case "surah_name":
                kind = .surahName(surah: Int(sqlite3_column_int(statement, 6)))
            case "basmallah":
                kind = .basmala
            default:
                let first = Int(sqlite3_column_int(statement, 4)), last = Int(sqlite3_column_int(statement, 5))
                kind = .ayah(
                    words: (first...last).map {
                        MushafWord(glyph: glyph[$0], isAyahEnd: ayahEnds.contains($0),
                                   ayah: indexOfAyah[ayahOfWord[$0]] ?? 0, topic: topicOfAyah[ayahOfWord[$0]])
                    },
                    centered: sqlite3_column_int(statement, 3) != 0
                )
            }
            guard (1...Self.pageCount).contains(page) else { return }
            linesByPage[page].append(MushafLine(number: number, kind: kind))
        }

        var surahStarts: [Int: Int] = [:]
        for page in 1...Self.pageCount {
            for line in linesByPage[page] {
                if case .surahName(let surah) = line.kind { surahStarts[surah] = surahStarts[surah] ?? page }
            }
        }
        surahStartPages = surahStarts

        pages = (1...Self.pageCount).map { number in
            let first = firstAyahOnPage[number]
            let ayahs = linesByPage[number].flatMap { line -> [Int] in
                if case .ayah(let words, _) = line.kind { return words.map(\.ayah) } else { return [] }
            }
            return MushafPage(
                number: number, lines: linesByPage[number], spokenAyat: spoken[number],
                ayahs: (ayahs.min() ?? 0)...(ayahs.max() ?? 0),
                surah: first?.sura_no ?? 1, juz: first?.jozz ?? 1
            )
        }
    }

    /// Runs a query on a bundled SQLite file, calling `row` for each result row.
    private static func query(_ url: URL, _ sql: String, row: (OpaquePointer) throws -> Void) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw LoadError.database("open \(url.lastPathComponent)")
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LoadError.database("prepare \(url.lastPathComponent)")
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { try row(statement) }
    }

    /// The surah being read on a page: the last surah that starts on or before it.
    func surah(containing page: Int) -> Int {
        surahStartPages.filter { $0.value <= page }.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 1
    }

    /// The juz' a page belongs to: the last juz' that starts on or before it.
    func juz(containing page: Int) -> Int {
        juzStartPages.filter { $0.value <= page }.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 1
    }

    func page(_ number: Int) -> MushafPage {
        pages[min(max(number, 1), Self.pageCount) - 1]
    }

    /// An ayah's surah and its number in the surah, from its number in the Quran (0..<6236).
    func reference(ofAyah ayah: Int) -> (surah: Int, ayah: Int) {
        let ayah = min(max(ayah, 0), Self.ayahCount - 1)
        guard let (surah, range) = surahAyahs.first(where: { $0.value.contains(ayah) }) else { return (1, 1) }
        return (surah, ayah - range.lowerBound + 1)
    }

    /// The page an ayah starts on: the first page that holds any of it.
    func page(ofAyah ayah: Int) -> Int {
        var low = 1, high = Self.pageCount
        while low < high {
            let middle = (low + high) / 2
            if pages[middle - 1].ayahs.upperBound >= ayah { high = middle } else { low = middle + 1 }
        }
        return low
    }
}
