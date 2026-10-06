import Foundation
import SQLite3

/// One line of a Mushaf page, as laid out in the 1421H Madinah print.
struct MushafLine: Hashable {
    enum Kind: Hashable {
        case surahName(surah: Int)
        case basmala
        /// The line's words in reading order, each as its glyph in the page font.
        case ayah(words: [String], centered: Bool)
    }

    var number: Int
    var kind: Kind
}

struct MushafPage: Hashable {
    var number: Int
    var lines: [MushafLine]
    /// The surah the page starts in, and its juz'.
    var surah: Int
    var juz: Int
}

/// Reads the bundled Quran data (`shared/quran`) and builds Mushaf pages.
///
/// Pages and words come from the QUL "KFGQPC V2 layout (1421H print)" and its glyphs;
/// surah names, juz' and the basmala come from the King Fahd Complex's official data.
final class MushafStore {
    static let pageCount = 604

    enum LoadError: Error {
        case missingResource(String)
        case database(String)
    }

    /// Official Arabic surah names, indexed by surah number.
    let surahNames: [Int: String]
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

        // Official data: surah names, juz' per page, and the basmala.
        struct OfficialAyah: Decodable {
            var sura_no: Int
            var sura_name_ar: String
            var aya_no: Int
            var page: Int
            var jozz: Int
            var aya_text: String
        }
        let official = try JSONDecoder().decode([OfficialAyah].self, from: Data(contentsOf: url("kfgqpc/hafs_smart_v8.json")))
        var names: [Int: String] = [:]
        var firstAyahOnPage: [Int: OfficialAyah] = [:]
        for ayah in official {
            names[ayah.sura_no] = names[ayah.sura_no] ?? ayah.sura_name_ar
            firstAyahOnPage[ayah.page] = firstAyahOnPage[ayah.page] ?? ayah
        }
        surahNames = names
        let fatiha = official.first { $0.sura_no == 1 && $0.aya_no == 1 }?.aya_text ?? ""
        basmala = fatiha.split(separator: " ").dropLast().joined(separator: " ")

        // QUL glyphs: word id → glyph.
        struct Word: Decodable { var id: Int; var text: String }
        let words = try JSONDecoder().decode([String: Word].self, from: Data(contentsOf: url("qul/qpc-v2.json")))
        var glyph = [String](repeating: "", count: words.count + 1)
        for word in words.values where word.id < glyph.count { glyph[word.id] = word.text }

        // QUL layout: 15 lines per page.
        var linesByPage = [[MushafLine]](repeating: [], count: Self.pageCount + 1)
        var db: OpaquePointer?
        guard sqlite3_open_v2(try url("qul/qpc-v2-15-lines.db").path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
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
                kind = .ayah(words: (first...last).map { glyph[$0] }, centered: sqlite3_column_int(statement, 3) != 0)
            }
            guard (1...Self.pageCount).contains(page) else { continue }
            linesByPage[page].append(MushafLine(number: number, kind: kind))
        }

        pages = (1...Self.pageCount).map { number in
            let first = firstAyahOnPage[number]
            return MushafPage(number: number, lines: linesByPage[number], surah: first?.sura_no ?? 1, juz: first?.jozz ?? 1)
        }
    }

    func page(_ number: Int) -> MushafPage {
        pages[min(max(number, 1), Self.pageCount) - 1]
    }
}
