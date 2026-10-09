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
        ("qul/qpc-v4-tajweed-15-lines.db", "4b3fb1cbe8dff749ab0173c4b86cb40fe3c48dd072f41d3c7e715654a9f843cd"),
        ("qul/qpc-v4.json", "40964a1b7932e9a69e0dfc0d58dce3b73e30a803febda119fd6828bcb75fac98"),
        ("qul/QCF_SurahHeader_COLOR-Regular.ttf", "de261a309bdd42262e1a268d5ead56b6ea8366cd59124baedea3903561d7370b"),
        ("qul/surah-header-ligatures.json", "c4480a1fb616685421ada1f9cbd36187c1c27c01d8d78d27a866858fdaf5c4f7"),
        ("qul/ayah-themes.db", "b3c20c4fab472586904543ed12c87e2ac616ce629ac18a125357408e50927a42"),
        ("qcf4.sha256", "7d2034c4e65b69b01337be804c9fb5934dee6b03b1b2e05f4fe9ec69810f28e2"),
    ])
    func fileMatchesRecordedChecksum(path: String, expected: String) throws {
        #expect(try sha256(of: path) == expected)
    }

    /// Every page font matches the manifest, and all 604 are present.
    @Test func pageFontsMatchManifest() throws {
        let manifestURL = try #require(MushafStore.resourceURL("qcf4.sha256"))
        let entries = try String(contentsOf: manifestURL, encoding: .utf8)
            .split(separator: "\n")
            .map { $0.split(separator: " ", omittingEmptySubsequences: true) }
        #expect(entries.count == MushafStore.pageCount)
        for entry in entries {
            #expect(try sha256(of: "qcf4/\(entry[1])") == String(entry[0]), "\(entry[1])")
        }
    }
}

/// How long it takes to load the Mushaf; printed so changes can be compared. The limit is on the loading thread's
/// own CPU time, so suites running alongside (which load the Mushaf too) don't make it look slower than it is.
struct MushafLoadTimeTests {
    @Test func loadsQuickly() throws {
        let clock = ContinuousClock()
        var store: MushafStore?
        let cpuStart = Self.threadCPUTime()
        let elapsed = try clock.measure { store = try MushafStore() }
        let cpu = Self.threadCPUTime() - cpuStart
        print("MushafStore load time: \(elapsed.formatted(.units(allowed: [.milliseconds]))), CPU \(Int(cpu * 1_000)) ms")
        #expect(store != nil)
        #expect(cpu < 2)
    }

    private static func threadCPUTime() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
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
        var surahs = 0, words = 0, ayahEnds = 0
        for number in 1...MushafStore.pageCount {
            for line in store.page(number).lines {
                switch line.kind {
                case .surahName: surahs += 1
                case .ayah(let lineWords, _):
                    words += lineWords.count
                    ayahEnds += lineWords.filter(\.isAyahEnd).count
                    #expect(!lineWords.contains { $0.glyph.isEmpty }, "empty glyph on page \(number) line \(line.number)")
                case .basmala: break
                }
            }
        }
        #expect(surahs == 114)
        // 77,432 words plus 6,236 ayah-end markers, as in the QUL glyph data.
        #expect(words == 83_668)
        #expect(ayahEnds == 6_236)
    }

    /// The 1441H layout puts every ayah on the same page, and ends it on the same line, as the King Fahd Complex's official data.
    @Test func everyAyahEndsWhereTheOfficialDataSays() throws {
        struct OfficialAyah: Decodable { var page: Int; var line_end: Int }
        let url = try #require(MushafStore.resourceURL("kfgqpc/hafs_smart_v8.json"))
        var official: [String: Int] = [:]
        for ayah in try JSONDecoder().decode([OfficialAyah].self, from: Data(contentsOf: url)) {
            official["\(ayah.page):\(ayah.line_end)", default: 0] += 1
        }
        var layout: [String: Int] = [:]
        for number in 1...MushafStore.pageCount {
            for line in store.page(number).lines {
                guard case .ayah(let words, _) = line.kind else { continue }
                let ends = words.filter(\.isAyahEnd).count
                if ends > 0 { layout["\(number):\(line.number)", default: 0] += ends }
            }
        }
        #expect(layout == official)
    }

    /// Every word has an outline to draw, and every page has tajweed colors to tint it with.
    /// Only one word has no width of its own: the pause sign after word 4 of Ghafir 40:77, page 475 line 14.
    @Test func everyWordHasOutlineAndEveryPageHasTajweed() throws {
        var zeroWidth: [String] = []
        for number in 1...MushafStore.pageCount {
            var colored = 0
            for line in store.page(number).lines {
                guard case .ayah(let words, _) = line.kind else { continue }
                for word in words {
                    let glyph = try #require(MushafFonts.word(word.glyph, page: number, size: 20), "page \(number) line \(line.number)")
                    #expect(!glyph.outline.isEmpty, "page \(number) line \(line.number)")
                    if !glyph.layers.isEmpty { colored += 1 }
                    if glyph.size.width <= 0 { zeroWidth.append("\(number):\(line.number)") }
                }
            }
            #expect(colored > 0, "page \(number) has no tajweed colors")
        }
        #expect(zeroWidth == ["475:14"])
    }

    /// The page fonts carry their own light and dark tajweed palettes; Aqra reads them rather than hardcoding colors.
    @Test func pageFontsCarryTajweedPalettes() throws {
        for number in [1, 300, 604] {
            let url = try #require(MushafStore.resourceURL(MushafFonts.pageFontPath(number)))
            let descriptor = try #require((CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first)
            let colors = TajweedColors(font: CTFontCreateWithFontDescriptor(descriptor, 20, nil))
            #expect(colors.colors.count == 16, "page \(number)")
            #expect(!colors.layers.isEmpty, "page \(number)")
        }
    }

    /// Words carry their ayah's topic section: al-Baqarah opens with 1–5, then 6–7. The stand-in topic data
    /// has 1,049 sections; its four gaps (2:134, 40:61, 54:45–55, 55:56–78) become sections of their own.
    @Test func wordsCarryTheirTopicSection() {
        var topics = Set<Int>(), wordsWithout = 0
        for number in 1...MushafStore.pageCount {
            for line in store.page(number).lines {
                guard case .ayah(let words, _) = line.kind else { continue }
                for word in words {
                    if let topic = word.topic { topics.insert(topic) } else { wordsWithout += 1 }
                }
            }
        }
        #expect(topics.count == 1_053)
        #expect(wordsWithout == 0)

        // Page 2: al-Baqarah 1–5 is one section and 6–7 the next.
        let pageTwo = store.page(2).lines.compactMap { line -> [MushafWord]? in
            if case .ayah(let words, _) = line.kind { return words } else { return nil }
        }.flatMap { $0 }
        let ayahTopics = pageTwo.filter(\.isAyahEnd).map(\.topic)
        #expect(ayahTopics.count == 5)
        #expect(Set(ayahTopics).count == 1)
    }

    /// Ayat are numbered 0..<6236 in Quran order; juz', surahs and pages know which they hold.
    @Test func ayahNumbersAndRanges() {
        #expect(store.juzAyahs[1] == 0...147)
        #expect(store.juzAyahs[30]?.count == 564)
        var next = 0
        for juz in 1...30 {
            let range = store.juzAyahs[juz]
            #expect(range?.lowerBound == next, "juz' \(juz)")
            next = (range?.upperBound ?? 0) + 1
        }
        #expect(next == MushafStore.ayahCount)
        #expect(store.surahAyahs[1] == 0...6 && store.surahAyahs[2]?.count == 286)
        #expect(store.surahAyahs[114]?.upperBound == MushafStore.ayahCount - 1)
        #expect(store.page(1).ayahs == 0...6 && store.page(2).ayahs == 7...11)

        // Words run in Quran order, each inside its page's range.
        var previous = 0
        for number in 1...MushafStore.pageCount {
            let page = store.page(number)
            for line in page.lines {
                guard case .ayah(let words, _) = line.kind else { continue }
                for word in words {
                    #expect(word.ayah >= previous && page.ayahs.contains(word.ayah), "page \(number)")
                    previous = word.ayah
                }
            }
        }
    }

    /// An ayah's surah and number, and the page it starts on.
    @Test func referencesAndPagesOfAyat() {
        #expect(store.reference(ofAyah: 0) == (1, 1))
        #expect(store.reference(ofAyah: 7) == (2, 1))
        #expect(store.reference(ofAyah: 7 + 254) == (2, 255))
        #expect(store.reference(ofAyah: MushafStore.ayahCount - 1) == (114, 6))
        #expect(store.page(ofAyah: 0) == 1 && store.page(ofAyah: 7) == 2 && store.page(ofAyah: 12) == 3)
        #expect(store.page(ofAyah: MushafStore.ayahCount - 1) == 604)
        // Every ayah's page holds it, and the page before doesn't.
        for ayah in stride(from: 0, to: MushafStore.ayahCount, by: 37) {
            let page = store.page(ofAyah: ayah)
            #expect(store.page(page).ayahs.contains(ayah), "ayah \(ayah)")
            if page > 1 { #expect(store.page(page - 1).ayahs.upperBound < ayah, "ayah \(ayah)") }
        }
    }

    /// A tap lands on the ayah drawn under it, or the nearest one on its line; headers have none.
    @Test func findsTheAyahUnderAPoint() {
        let size = CGSize(width: 402, height: 874)
        let page = store.page(2)
        let metrics = PageMetrics(size: size)
        let top = metrics.linesTop(count: page.lines.count)
        let left = metrics.textLeft(in: size)
        // Line 3 opens al-Baqarah 1 (ayah 7, after al-Fatiha's seven) at its right end.
        #expect(MushafPageView.ayah(at: CGPoint(x: left + metrics.textWidth - 4, y: top + 2.5 * metrics.lineHeight), on: page, size: size) == 7)
        // The last line, al-Baqarah 5, is centered: a point in its empty left margin takes the nearest word.
        #expect(MushafPageView.ayah(at: CGPoint(x: left + 2, y: top + 7.5 * metrics.lineHeight), on: page, size: size) == 11)
        // The surah header and the basmala hold no ayah.
        #expect(MushafPageView.ayah(at: CGPoint(x: size.width / 2, y: top + 0.5 * metrics.lineHeight), on: page, size: size) == nil)
        #expect(MushafPageView.ayah(at: CGPoint(x: size.width / 2, y: top + 1.5 * metrics.lineHeight), on: page, size: size) == nil)
    }

    @Test func indexCoversEverySurahAndJuz() {
        #expect(store.surahHeaders.count == 114)
        #expect(store.surahStartPages.count == 114)
        #expect(store.surahStartPages[1] == 1 && store.surahStartPages[2] == 2 && store.surahStartPages[114] == 604)
        #expect(store.juzStartPages.count == 30)
        #expect(store.juzStartPages[1] == 1 && store.juzStartPages[30] == 582)
    }

    @Test func surahNamesAndBasmalaComeFromOfficialData() {
        #expect(store.surahNames.count == 114)
        #expect(store.surahNames[2] == "البَقَرَة")
        #expect(store.basmala.split(separator: " ").count == 4)
    }

    /// Every word's glyph exists in its own page font, so no word can render as a missing-glyph box.
    @Test func everyWordRendersInItsPageFont() throws {
        for number in 1...MushafStore.pageCount {
            let url = try #require(MushafStore.resourceURL(MushafFonts.pageFontPath(number)))
            let descriptor = try #require((CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first)
            let font = CTFontCreateWithFontDescriptor(descriptor, 20, nil)
            for line in store.page(number).lines {
                guard case .ayah(let words, _) = line.kind else { continue }
                for word in words {
                    let units = Array(word.glyph.utf16)
                    var glyphs = [CGGlyph](repeating: 0, count: units.count)
                    let found = CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
                    #expect(found && !glyphs.contains(0), "page \(number) line \(line.number)")
                }
            }
        }
    }

    /// Every surah header glyph exists in the surah header font.
    @Test func everySurahHeaderRendersInHeaderFont() throws {
        let url = try #require(MushafStore.resourceURL("qul/QCF_SurahHeader_COLOR-Regular.ttf"))
        let descriptor = try #require((CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first)
        let font = CTFontCreateWithFontDescriptor(descriptor, 20, nil)
        for surah in 1...114 {
            let units = Array((store.surahHeaders[surah] ?? "").utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            #expect(!units.isEmpty && CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) && !glyphs.contains(0), "surah \(surah)")
        }
    }

    @Test func findsTheSurahAndJuzOfAnyPage() {
        #expect(store.surah(containing: 1) == 1)
        #expect(store.surah(containing: 49) == 2)   // still al-Baqarah
        #expect(store.surah(containing: 50) == 3)   // Al 'Imran starts here
        #expect(store.surah(containing: 384) == 27) // an-Naml
        #expect(store.surah(containing: 385) == 28) // al-Qasas starts mid-page
        #expect(store.surah(containing: 604) == 114)
        #expect(store.juz(containing: 1) == 1)
        #expect(store.juz(containing: 385) == 20)
        #expect(store.juz(containing: 604) == 30)
    }

    /// VoiceOver reads each page from the official plain text, one entry per ayah on the page.
    @Test func pagesCarryTheirAyatAsPlainText() {
        #expect(store.page(1).spokenAyat.count == 7)
        #expect(store.page(1).spokenAyat.first?.hasPrefix("بسم الله الرحمن الرحيم") == true)
        let total = (1...MushafStore.pageCount).reduce(0) { $0 + store.page($1).spokenAyat.count }
        #expect(total == 6_236)
        // Each entry knows its ayah, so a revision can leave out the veiled ones.
        #expect(store.page(1).spokenAyahs == Array(0...6))
        let ayahs = (1...MushafStore.pageCount).flatMap { store.page($0).spokenAyahs }
        #expect(ayahs == Array(0..<MushafStore.ayahCount))
        #expect(store.page(50).spokenAyahs.allSatisfy { store.page(50).ayahs.contains($0) })
    }
}

/// A build without the page fonts must explain itself instead of drawing missing glyphs.
struct MushafMissingFontsTests {
    private final class TestBundleMarker {}

    @Test func explainsMissingPageFonts() {
        // The test bundle has no Quran data, so no page fonts either.
        let bundle = Bundle(for: TestBundleMarker.self)
        #expect {
            _ = try MushafStore(bundle: bundle)
        } throws: { error in
            guard case MushafStore.LoadError.missingPageFonts(let found) = error else { return false }
            return found == 0 && "\(error)".contains("fetch-mushaf-fonts.sh")
        }
    }
}
