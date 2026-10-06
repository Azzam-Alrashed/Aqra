import Foundation
import SQLite3

/// A word on a Mushaf page: its glyph in the page font, and whether it's an ayah-end marker.
struct MushafWord: Hashable {
    var glyph: String
    var isAyahEnd: Bool
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
        var lastWordOfAyah: [String: (position: Int, id: Int)] = [:]
        for word in words.values where word.id < glyph.count {
            glyph[word.id] = word.text
            let key = "\(word.surah):\(word.ayah)", position = Int(word.word) ?? 0
            if position > (lastWordOfAyah[key]?.position ?? 0) { lastWordOfAyah[key] = (position, word.id) }
        }
        let ayahEnds = Set(lastWordOfAyah.values.map(\.id))

        // QUL layout: 15 lines per page.
        var linesByPage = [[MushafLine]](repeating: [], count: Self.pageCount + 1)
        var db: OpaquePointer?
        guard sqlite3_open_v2(try url("qul/qpc-v4-tajweed-15-lines.db").path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw LoadError.database("open")
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT page_number, line_number, line_type, is_centered, first_word_id, last_word_id, surah_number FROM pages ORDER BY page_number, line_number"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw LoadError.database("prepare") }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
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
                    words: (first...last).map { MushafWord(glyph: glyph[$0], isAyahEnd: ayahEnds.contains($0)) },
                    centered: sqlite3_column_int(statement, 3) != 0
                )
            }
            guard (1...Self.pageCount).contains(page) else { continue }
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
            return MushafPage(
                number: number, lines: linesByPage[number], spokenAyat: spoken[number],
                surah: first?.sura_no ?? 1, juz: first?.jozz ?? 1
            )
        }
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
}
