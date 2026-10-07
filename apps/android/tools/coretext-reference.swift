// Measures the Mushaf page fonts with CoreText, the text engine the iOS app draws with, so the Android app's own font
// reader can be checked against it (see apps/android/README.md):
//
//   swiftc -O apps/android/tools/coretext-reference.swift -o build/coretext-reference
//   build/coretext-reference shared/quran apps/android/build/coretext
//
// It writes five tables, in font units (y up):
//   glyphs.tsv: page, glyph, minX, minY, maxX, maxY, area — every glyph of every page font;
//   words.tsv: page, word id, width, then each glyph as glyph@x in the order CoreText lays them out;
//   metrics.tsv: page, ascent, descent, leading;
//   texts.tsv: the basmala (in the Hafs Smart font) and each surah header (in the surah header font): name, ascent,
//   descent, width, then each glyph as glyph@x;
//   ayat.tsv: every word of every ayah in the Hafs Smart font, each set on its own as the stage tests draw them: ayah,
//   word, width, then each glyph as glyph@x@y.
import CoreText
import Foundation
import SQLite3

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: coretext-reference <shared/quran> <output directory>")
    exit(2)
}
let quran = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func font(page: Int) -> CTFont {
    let url = quran.appendingPathComponent("qcf4/p\(page).woff2")
    let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as! [CTFontDescriptor])[0]
    let font = CTFontCreateWithFontDescriptor(descriptor, 1, nil)
    // At a size of one em in font units, outlines come out in font units.
    return CTFontCreateCopyWithAttributes(font, CGFloat(CTFontGetUnitsPerEm(font)), nil, nil)
}

/// The signed area of a path, from its lines and curves (Green's theorem).
func area(_ path: CGPath) -> Double {
    var total = 0.0
    var start = CGPoint.zero, last = CGPoint.zero
    func cross(_ a: CGPoint, _ b: CGPoint) -> Double { Double(a.x * b.y - a.y * b.x) }
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint:
            total += cross(last, start) / 2
            start = points[0]; last = start
        case .addLineToPoint:
            total += cross(last, points[0]) / 2
            last = points[0]
        case .addQuadCurveToPoint:
            let c = points[0], e = points[1]
            total += (cross(last, e) / 3 + 2.0 / 3 * (cross(last, c) + cross(c, e))) / 2
            last = e
        case .addCurveToPoint:
            fatalError("Cubic curves aren't expected in TrueType outlines")
        case .closeSubpath:
            total += cross(last, start) / 2
            last = start
        @unknown default:
            break
        }
    }
    return total
}

func format(_ value: CGFloat) -> String { String(format: "%.3f", Double(value)) }

// Words by page, from the layout and the glyph data.
var db: OpaquePointer?
sqlite3_open_v2(quran.appendingPathComponent("qul/qpc-v4-tajweed-15-lines.db").path, &db, SQLITE_OPEN_READONLY, nil)
var statement: OpaquePointer?
sqlite3_prepare_v2(db, "SELECT page_number, first_word_id, last_word_id FROM pages WHERE line_type = 'ayah' ORDER BY page_number, line_number", -1, &statement, nil)
var wordsByPage: [Int: [Int]] = [:]
while sqlite3_step(statement) == SQLITE_ROW {
    let page = Int(sqlite3_column_int(statement, 0))
    let first = Int(sqlite3_column_int(statement, 1)), last = Int(sqlite3_column_int(statement, 2))
    wordsByPage[page, default: []] += Array(first...last)
}
sqlite3_finalize(statement)
sqlite3_close(db)
let glyphData = try JSONSerialization.jsonObject(with: Data(contentsOf: quran.appendingPathComponent("qul/qpc-v4.json"))) as! [String: [String: Any]]
var text: [Int: String] = [:]
for word in glyphData.values { text[word["id"] as! Int] = word["text"] as? String }

var glyphs = "", words = "", metrics = ""
for page in 1...604 {
    let font = font(page: page)
    metrics += "\(page)\t\(format(CTFontGetAscent(font)))\t\(format(CTFontGetDescent(font)))\t\(format(CTFontGetLeading(font)))\n"
    for glyph in 0..<CTFontGetGlyphCount(font) {
        guard let path = CTFontCreatePathForGlyph(font, CGGlyph(glyph), nil), !path.isEmpty else { continue }
        let box = path.boundingBoxOfPath
        glyphs += "\(page)\t\(glyph)\t\(format(box.minX))\t\(format(box.minY))\t\(format(box.maxX))\t\(format(box.maxY))\t\(String(format: "%.2f", area(path)))\n"
    }
    for id in wordsByPage[page] ?? [] {
        let string = text[id] ?? ""
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        var placed: [String] = []
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var runGlyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &runGlyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            for i in 0..<count { placed.append("\(runGlyphs[i])@\(format(positions[i].x))") }
        }
        words += "\(page)\t\(id)\t\(format(CTLineGetTypographicBounds(line, nil, nil, nil)))\t\(placed.joined(separator: " "))\n"
    }
}
// The two lines drawn as text: the basmala and the surah headers.
func textFont(_ path: String) -> CTFont {
    let url = quran.appendingPathComponent(path)
    let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as! [CTFontDescriptor])[0]
    let font = CTFontCreateWithFontDescriptor(descriptor, 1, nil)
    return CTFontCreateCopyWithAttributes(font, CGFloat(CTFontGetUnitsPerEm(font)), nil, nil)
}
func layout(_ string: String, _ font: CTFont, name: String) -> String {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    var placed: [String] = []
    for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
        let count = CTRunGetGlyphCount(run)
        var runGlyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(), &runGlyphs)
        CTRunGetPositions(run, CFRange(), &positions)
        for i in 0..<count { placed.append("\(runGlyphs[i])@\(format(positions[i].x))") }
    }
    return "\(name)\t\(format(CTFontGetAscent(font)))\t\(format(CTFontGetDescent(font)))\t\(format(CTLineGetTypographicBounds(line, nil, nil, nil)))\t\(placed.joined(separator: " "))\n"
}
struct OfficialAyah: Decodable { var sura_no: Int; var aya_no: Int; var aya_text: String }
let official = try JSONDecoder().decode([OfficialAyah].self, from: Data(contentsOf: quran.appendingPathComponent("kfgqpc/hafs_smart_v8.json")))
let fatiha = official.first { $0.sura_no == 1 && $0.aya_no == 1 }!.aya_text
let basmala = fatiha.split(separator: " ").dropLast().joined(separator: " ")
var texts = layout(basmala, textFont("kfgqpc/HafsSmart_08.ttf"), name: "basmala")
let headers = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: quran.appendingPathComponent("qul/surah-header-ligatures.json")))
let headerFont = textFont("qul/QCF_SurahHeader_COLOR-Regular.ttf")
for surah in 1...114 {
    texts += layout(headers["surah-\(surah)"]!.trimmingCharacters(in: .whitespaces), headerFont, name: "surah-\(surah)")
}
try texts.write(to: output.appendingPathComponent("texts.tsv"), atomically: true, encoding: .utf8)

// Every ayah in the Hafs Smart font, word by word.
let hafs = textFont("kfgqpc/HafsSmart_08.ttf")
var ayat = ""
for (index, ayah) in official.enumerated() {
    for (number, word) in ayah.aya_text.split(separator: " ").enumerated() {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(word), attributes: [NSAttributedString.Key(kCTFontAttributeName as String): hafs]))
        var placed: [String] = []
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var runGlyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &runGlyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            for i in 0..<count { placed.append("\(runGlyphs[i])@\(format(positions[i].x))@\(format(positions[i].y))") }
        }
        ayat += "\(index)\t\(number)\t\(format(CTLineGetTypographicBounds(line, nil, nil, nil)))\t\(placed.joined(separator: " "))\n"
    }
}
try ayat.write(to: output.appendingPathComponent("ayat.tsv"), atomically: true, encoding: .utf8)

try glyphs.write(to: output.appendingPathComponent("glyphs.tsv"), atomically: true, encoding: .utf8)
try words.write(to: output.appendingPathComponent("words.tsv"), atomically: true, encoding: .utf8)
try metrics.write(to: output.appendingPathComponent("metrics.tsv"), atomically: true, encoding: .utf8)
print("Wrote \(glyphs.split(separator: "\n").count) glyphs and \(words.split(separator: "\n").count) words to \(output.path)")
