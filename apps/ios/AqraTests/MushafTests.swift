import CoreText
import CryptoKit
import Foundation
import Testing
@testable import Aqra

/// Guards the bundled Quran data (shared/quran) against any change, and checks the Mushaf built from it.
struct MushafDataTests {
    private func sha256(of path: String) throws -> String {
        let url = try #require(MushafStore.resourceURL(path), "missing \(path)")
        return SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    /// The SHA-256 values recorded in shared/quran/README.md.
    @Test(arguments: [
        ("kfgqpc/hafs_smart_v8.json", "a272a119a4272f10cf42d8e389857b469183d3217fa23aa38b6a7331d0ac4aa2"),
        ("kfgqpc/HafsSmart_08.ttf", "18c5641d1a9433499660122eccc6388bf89b9c8b752e5957aff41a2bed2c976b"),
        ("qul/qpc-v2-15-lines.db", "e4df98f35dd3b8927ff096337c8739e0f0b12c8ba622834c345eaa4c3e28dd8c"),
        ("qul/qpc-v2.json", "40964a1b7932e9a69e0dfc0d58dce3b73e30a803febda119fd6828bcb75fac98"),
        ("qcf2.sha256", "1897276392759f73839ee1b1255c4b6bf97c6c36e108ed6172d560f2f09b34c3"),
    ])
    func fileMatchesRecordedChecksum(path: String, expected: String) throws {
        #expect(try sha256(of: path) == expected)
    }

    /// Every page font matches the manifest, and all 604 are present.
    @Test func pageFontsMatchManifest() throws {
        let manifestURL = try #require(MushafStore.resourceURL("qcf2.sha256"))
        let entries = try String(contentsOf: manifestURL, encoding: .utf8)
            .split(separator: "\n")
            .map { $0.split(separator: " ", omittingEmptySubsequences: true) }
        #expect(entries.count == MushafStore.pageCount)
        for entry in entries {
            #expect(try sha256(of: "qcf2/\(entry[1])") == String(entry[0]), "\(entry[1])")
        }
    }
}

@MainActor
struct MushafStoreTests {
    private let store: MushafStore

    init() throws {
        store = try MushafStore()
    }

    @Test func pagesHaveFifteenLines() {
        for number in 1...MushafStore.pageCount {
            let page = store.page(number)
            #expect(page.number == number)
            // Pages 1 and 2 (al-Fatiha and the start of al-Baqarah) are shorter in the Madinah Mushaf.
            #expect(page.lines.count == (number <= 2 ? 8 : 15), "page \(number) has \(page.lines.count) lines")
        }
    }

    @Test func layoutHasEverySurahAndWord() {
        var surahs = 0, words = 0
        for number in 1...MushafStore.pageCount {
            for line in store.page(number).lines {
                switch line.kind {
                case .surahName: surahs += 1
                case .ayah(let lineWords, _):
                    words += lineWords.count
                    #expect(!lineWords.contains(""), "empty glyph on page \(number) line \(line.number)")
                case .basmala: break
                }
            }
        }
        #expect(surahs == 114)
        // 77,432 words plus 6,236 ayah-end markers, as in the QUL glyph data.
        #expect(words == 83_668)
    }

    @Test func surahNamesAndBasmalaComeFromOfficialData() {
        #expect(store.surahNames.count == 114)
        #expect(store.surahNames[2] == "البَقَرَة")
        #expect(store.basmala.split(separator: " ").count == 4)
    }

    /// Every word's glyph exists in its own page font, so no word can render as a missing-glyph box.
    @Test func everyWordRendersInItsPageFont() throws {
        for number in 1...MushafStore.pageCount {
            let url = try #require(MushafStore.resourceURL(String(format: "qcf2/QCF2%03d.ttf", number)))
            let descriptor = try #require((CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first)
            let font = CTFontCreateWithFontDescriptor(descriptor, 20, nil)
            for line in store.page(number).lines {
                guard case .ayah(let words, _) = line.kind else { continue }
                for word in words {
                    let units = Array(word.utf16)
                    var glyphs = [CGGlyph](repeating: 0, count: units.count)
                    let found = CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
                    #expect(found && !glyphs.contains(0), "page \(number) line \(line.number)")
                }
            }
        }
    }
}
