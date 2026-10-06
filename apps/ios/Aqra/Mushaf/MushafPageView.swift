import CoreText
import SwiftUI

/// The Mushaf's look: warm paper, dark ink, gold ornament — and in dark mode,
/// a deep warm page (not pure black) with cream ink and lighter gold.
enum MushafStyle {
    static let paper = Color(light: 0xFBF7EE, dark: 0x1A1612)
    static let ink = Color(light: 0x1C1712, dark: 0xEFE6D4)
    static let chrome = Color(light: 0x8A7A64, dark: 0xA8977B)
    static let gold = Color(light: 0xC9A24A, dark: 0xD4B160)
    /// The surah header frame and calligraphy.
    static let ornament = Color(light: 0x9A7440, dark: 0xC9A35E)
    /// Ayah-end markers: a soft disc behind a brown-gold rosette and number.
    static let markerFill = Color(light: 0xF1E4C8, dark: 0x3A2F22)
    static let marker = Color(light: 0x8C6A3F, dark: 0xD9BC82)
    /// Topic sections, in the soft pastels of a colored Mushaf: mint, sky, rose, lavender, butter and peach.
    /// Neighboring sections always take different colors.
    static let topics = [
        Color(light: 0xD9F0E0, dark: 0x22382B), Color(light: 0xD7EAF6, dark: 0x1F3243),
        Color(light: 0xF6DCE3, dark: 0x3F252D), Color(light: 0xE5DEF3, dark: 0x2D2843),
        Color(light: 0xF6EBC6, dark: 0x3B3320), Color(light: 0xF8DFCE, dark: 0x40291E),
    ]

    static func topic(_ section: Int) -> Color {
        topics[section % topics.count]
    }
}

/// Loads the Mushaf fonts straight from the bundle, without registering them system-wide.
@MainActor
enum MushafFonts {
    private static var descriptors: [String: CTFontDescriptor] = [:]
    /// Fonts and words already made, by path and size, so pages don't rebuild them on every render.
    private static var fonts: [String: Font] = [:]
    private static var coreTextFonts: [String: CTFont] = [:]
    private static var colorTables: [String: TajweedColors] = [:]
    /// The words of the pages read most recently; older pages are let go so reading the whole Mushaf stays light.
    private static var pageWords: [Int: [String: WordGlyph]] = [:]
    private static var recentPages: [Int] = []
    private static let pagesKept = 12

    /// The page's own QCF V4 font (1441H print), whose glyphs are that page's words, with the tajweed colors built in.
    nonisolated static func pageFontPath(_ number: Int) -> String {
        "qcf4/p\(number).woff2"
    }

    /// The Complex's Hafs Smart font, used for the basmala lines.
    static func hafsSmart(size: CGFloat) -> Font? {
        font(at: "kfgqpc/HafsSmart_08.ttf", size: size)
    }

    /// The surah header font: one glyph draws a surah's whole framed title.
    static func surahHeader(size: CGFloat) -> Font? {
        font(at: "qul/QCF_SurahHeader_COLOR-Regular.ttf", size: size)
    }

    /// A word of a page, built from its page font's outlines and laid out as Text would place it
    /// (baseline at the font's ascent). Words are drawn from outlines rather than as Text because the
    /// page fonts carry their own colors, which Text would always draw in black on the light palette.
    static func word(_ text: String, page: Int, size: CGFloat) -> WordGlyph? {
        keep(page)
        let key = "\(size)#\(text)"
        if let cached = pageWords[page]?[key] { return cached }
        let path = pageFontPath(page)
        guard let font = coreTextFont(at: path, size: size) else { return nil }
        let colors = colorTables[path] ?? TajweedColors(font: font)
        colorTables[path] = colors

        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let ascent = CTFontGetAscent(font)
        // Font coordinates have y up from the baseline; views have y down from the top.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: ascent)
        let outline = CGMutablePath()
        var layers: [TajweedLayer] = []
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                let place = CGAffineTransform(translationX: position.x, y: position.y).concatenating(flip)
                if let path = CTFontCreatePathForGlyph(font, glyph, nil) { outline.addPath(path, transform: place) }
                // Only the colored layers are kept; the text itself is always the plain outline.
                for layer in colors.layers[glyph] ?? [] {
                    guard let entry = layer.entry, colors.colors.indices.contains(entry), let color = colors.colors[entry],
                          let path = CTFontCreatePathForGlyph(font, layer.glyph, nil) else { continue }
                    layers.append(TajweedLayer(color: color, path: Path(path).applying(place)))
                }
            }
        }
        let word = WordGlyph(
            outline: Path(outline),
            layers: layers,
            inkBox: outline.boundingBoxOfPath,
            size: CGSize(width: CTLineGetTypographicBounds(line, nil, nil, nil),
                         height: ascent + CTFontGetDescent(font) + CTFontGetLeading(font))
        )
        pageWords[page, default: [:]][key] = word
        return word
    }

    /// Marks a page as just read, and lets go of the words and fonts of pages read long ago.
    private static func keep(_ page: Int) {
        guard recentPages.last != page else { return }
        recentPages.removeAll { $0 == page }
        recentPages.append(page)
        while recentPages.count > pagesKept {
            let dropped = recentPages.removeFirst(), path = pageFontPath(dropped)
            pageWords[dropped] = nil
            descriptors[path] = nil
            colorTables[path] = nil
            coreTextFonts = coreTextFonts.filter { !$0.key.hasPrefix("\(path)@") }
        }
    }

    private static func font(at path: String, size: CGFloat) -> Font? {
        let key = "\(path)@\(size)"
        if let cached = fonts[key] { return cached }
        guard let coreText = coreTextFont(at: path, size: size) else { return nil }
        let font = Font(coreText)
        fonts[key] = font
        return font
    }

    private static func coreTextFont(at path: String, size: CGFloat) -> CTFont? {
        let key = "\(path)@\(size)"
        if let cached = coreTextFonts[key] { return cached }
        if descriptors[path] == nil,
           let url = MushafStore.resourceURL(path),
           let found = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let first = found.first {
            descriptors[path] = first
        }
        guard let descriptor = descriptors[path] else { return nil }
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        coreTextFonts[key] = font
        return font
    }
}

/// A word in view coordinates, inside a frame the size Text would give it.
struct WordGlyph {
    /// The whole word as one outline. This is the text as drawn, with or without tajweed.
    var outline: Path
    /// The word's colored tajweed layers in drawing order, painted only inside the outline.
    var layers: [TajweedLayer]
    var inkBox: CGRect
    var size: CGSize
}

struct TajweedLayer {
    var color: Color
    var path: Path
}

/// A page font's tajweed coloring, read from the font itself: which colored layers make up each glyph
/// (its COLR table) and the colors of its palettes (its CPAL table). The fonts aren't modified.
///
/// The color layers are only used to tint the plain outline, never drawn as text on their own: in these
/// fonts (still being proofread) they add hairline boxes and ellipses around some marks on most pages,
/// drop the pause sign on word 10 of al-Baqarah 2:268, and sit slightly off the plain outline in a few words.
struct TajweedColors {
    /// Each colored glyph's layers, bottom first, with the palette entry each is painted in.
    private(set) var layers: [CGGlyph: [(glyph: CGGlyph, entry: Int?)]] = [:]
    /// Each palette entry's tajweed color, from the font's light palette (0) and dark palette (1);
    /// nil for the entries that are the text's own black, which stay in Aqra's ink.
    private(set) var colors: [Color?] = []

    init(font: CTFont) {
        guard let colr = CTFontCopyTable(font, CTFontTableTag(kCTFontTableCOLR), []) as Data?,
              let cpal = CTFontCopyTable(font, CTFontTableTag(kCTFontTableCPAL), []) as Data?,
              colr.count >= 14, cpal.count >= 12 else { return }
        func u16(_ data: Data, _ offset: Int) -> Int {
            guard offset + 2 <= data.count else { return 0 }
            return Int(data[data.startIndex + offset]) << 8 | Int(data[data.startIndex + offset + 1])
        }
        func u32(_ data: Data, _ offset: Int) -> Int { u16(data, offset) << 16 | u16(data, offset + 2) }

        // CPAL: palettes of BGRA color records.
        let entries = u16(cpal, 2), palettes = u16(cpal, 4), records = u32(cpal, 8)
        func color(palette: Int, entry: Int) -> UInt32 {
            let record = records + 4 * (u16(cpal, 12 + 2 * palette) + entry)
            guard record + 4 <= cpal.count else { return 0 }
            let b = UInt32(cpal[cpal.startIndex + record]), g = UInt32(cpal[cpal.startIndex + record + 1]),
                r = UInt32(cpal[cpal.startIndex + record + 2])
            return r << 16 | g << 8 | b
        }
        guard palettes >= 2 else { return }
        colors = (0..<entries).map { entry in
            let light = color(palette: 0, entry: entry), dark = color(palette: 1, entry: entry)
            let isText = (light >> 16) & 0xFF < 0x20 && (light >> 8) & 0xFF < 0x20 && light & 0xFF < 0x20
            return isText ? nil : Color(light: light, dark: dark)
        }

        // COLR version 0: base glyph records, each pointing at a run of layer records.
        let baseCount = u16(colr, 2), baseOffset = u32(colr, 4), layerOffset = u32(colr, 8)
        for index in 0..<baseCount {
            let record = baseOffset + 6 * index
            let first = u16(colr, record + 2), count = u16(colr, record + 4)
            layers[CGGlyph(u16(colr, record))] = (0..<count).map { layer in
                let entry = u16(colr, layerOffset + 4 * (first + layer) + 2)
                // 0xFFFF means "the text color".
                return (CGGlyph(u16(colr, layerOffset + 4 * (first + layer))), entry == 0xFFFF ? nil : entry)
            }
        }
    }
}

extension EnvironmentValues {
    /// Whether the Mushaf shows the page fonts' tajweed colors.
    @Entry var mushafTajweed = true
    /// Whether the Mushaf colors each topic section with a soft highlight behind its words.
    @Entry var mushafTopics = true
}

/// One Mushaf page: 15 lines in the page's own font, framed by the surah, juz' and page number.
/// Memorized ayat sit on their topic section's color; in marking mode, taps and drags mark ayat.
struct MushafPageView: View {
    var page: MushafPage
    var store: MushafStore
    @Environment(\.mushafTajweed) private var tajweed
    @Environment(\.mushafTopics) private var topics
    @Environment(MemorizationStore.self) private var memorization: MemorizationStore?
    @Environment(MarkingSession.self) private var marking: MarkingSession?

    var body: some View {
        GeometryReader { geometry in
            let metrics = PageMetrics(size: geometry.size)
            VStack(spacing: 0) {
                header.frame(height: PageMetrics.chrome).padding(.top, metrics.topInset)
                VStack(spacing: 0) {
                    ForEach(page.lines, id: \.self) { line in
                        lineView(line, metrics: metrics)
                            .frame(width: metrics.textWidth, height: metrics.lineHeight)
                    }
                }
                .frame(maxHeight: .infinity)
                footer.frame(height: PageMetrics.chrome)
            }
            .padding(.horizontal, metrics.margin)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(MushafStyle.paper)
        .overlay { if let marking { markingLayer(marking) } }
        .environment(\.layoutDirection, .rightToLeft)
        // The words are font glyphs that VoiceOver can't read; give it the page in plain text instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    /// Marking mode: a tap marks or unmarks an ayah; pressing a moment, then dragging, marks every ayah crossed.
    private func markingLayer(_ marking: MarkingSession) -> some View {
        GeometryReader { geometry in
            // Both gestures run alongside the pager's swipe, so pages still turn in marking mode;
            // the pager holds still only once a press has turned into a drag that marks.
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        if let ayah = Self.ayah(at: value.location, on: page, size: geometry.size) { marking.tap(ayah) }
                    }
                )
        }
        // Locations are measured from the page's left edge, like the lines' own layout.
        .environment(\.layoutDirection, .leftToRight)
    }

    /// The ayah under a point on a page of the given size: the word on that line whose box holds the point,
    /// or the nearest one. Nil off the ayah lines (headers, the basmala and the margins above and below).
    static func ayah(at point: CGPoint, on page: MushafPage, size: CGSize) -> Int? {
        let metrics = PageMetrics(size: size)
        let top = metrics.linesTop(count: page.lines.count)
        let index = Int(floor((point.y - top) / metrics.lineHeight))
        guard page.lines.indices.contains(index), case .ayah(let words, let centered) = page.lines[index].kind else { return nil }
        let glyphs = words.map { MushafFonts.word($0.glyph, page: page.number, size: metrics.fontSize) }
        let widths = glyphs.map { $0?.size.width ?? 0 }
        let lefts = AyahLineLayout.lefts(widths: widths, lineWidth: metrics.textWidth, centered: centered,
                                          wordSpacing: metrics.wordSpacing)
        let x = point.x - metrics.textLeft(in: size)
        let nearest = words.indices.filter { widths[$0] > 0 }.min { a, b in
            distance(x, from: lefts[a], width: widths[a]) < distance(x, from: lefts[b], width: widths[b])
        }
        return nearest.map { words[$0].ayah }
    }

    private static func distance(_ x: CGFloat, from left: CGFloat, width: CGFloat) -> CGFloat {
        x < left ? left - x : x > left + width ? x - left - width : 0
    }

    private var accessibilityText: String {
        let surah = store.surahNames[page.surah] ?? ""
        let heading = "سورة \(surah)، الجزء \(arabic(page.juz))، الصفحة \(arabic(page.number))."
        return ([heading] + page.spokenAyat).joined(separator: " ")
    }

    private func arabic(_ number: Int) -> String {
        number.formatted(.number.locale(Locale(identifier: "ar@numbers=arab")))
    }

    @ViewBuilder
    private func lineView(_ line: MushafLine, metrics: PageMetrics) -> some View {
        let fontSize = metrics.fontSize, height = metrics.lineHeight
        switch line.kind {
        case .surahName(let surah):
            Text(verbatim: store.surahHeaders[surah] ?? "")
                .font(MushafFonts.surahHeader(size: metrics.textWidth * 0.96 / PageMetrics.headerWidthInEm))
                .foregroundStyle(MushafStyle.ornament)
                .fixedSize()
        case .basmala:
            // The basmala takes the color of the surah's first section once its first ayah is memorized.
            let color = topics ? highlight(for: firstWord(after: line))?.color : nil
            Text(verbatim: store.basmala)
                .font(MushafFonts.hafsSmart(size: fontSize * 1.05))
                .foregroundStyle(MushafStyle.ink)
                .fixedSize()
                .padding(.horizontal, color == nil ? 0 : fontSize * 0.5)
                .frame(height: color == nil ? nil : height * TopicHighlight.height)
                .background { if let color { RoundedRectangle(cornerRadius: height * TopicHighlight.cornerRadius).fill(color) } }
        case .ayah(let words, let centered):
            let glyphs = words.compactMap { word in
                MushafFonts.word(word.glyph, page: page.number, size: fontSize).map {
                    LineWord(isAyahEnd: word.isAyahEnd, highlight: topics ? highlight(for: word) : nil, glyph: $0)
                }
            }
            AyahLine(words: glyphs, centered: centered, tajweed: tajweed, wordSpacing: metrics.wordSpacing)
        }
    }

    /// A memorized word's highlight; nil for words not memorized, which stay on plain paper.
    private func highlight(for word: MushafWord?) -> TopicHighlight? {
        guard let word, let topic = word.topic, let memory = memorization?.memory(ofAyah: word.ayah) else { return nil }
        return TopicHighlight(topic: topic, strength: memory.strength)
    }

    /// The first word after a line on this page.
    private func firstWord(after line: MushafLine) -> MushafWord? {
        for next in page.lines where next.number > line.number {
            if case .ayah(let words, _) = next.kind { return words.first }
        }
        return nil
    }

    private var header: some View {
        HStack {
            Text(verbatim: "الجزء \(page.juz.formatted(.number.locale(Locale(identifier: "ar@numbers=arab"))))")
            Spacer()
            Text(verbatim: store.surahNames[page.surah] ?? "")
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(MushafStyle.chrome)
        .padding(.top, 4)
    }

    private var footer: some View {
        Text(verbatim: page.number.formatted(.number.locale(Locale(identifier: "ar@numbers=arab"))))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(MushafStyle.chrome)
            .padding(.horizontal, 14)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(MushafStyle.gold.opacity(0.6), lineWidth: 1))
    }
}

/// Where everything sits on a page of a given size. The page view and its marking layer both use it,
/// so a tap lands on exactly the ayah drawn under it.
struct PageMetrics {
    /// The words of a full 1441H line add up to at most 17 em in the QCF V4 fonts; leave room for the word gaps.
    static let lineWidthInEm: CGFloat = 17.4
    /// A surah header glyph is 3.3 em wide.
    static let headerWidthInEm: CGFloat = 3.303
    static let linesPerPage: CGFloat = 15
    /// The header and footer bands.
    static let chrome: CGFloat = 30

    var margin: CGFloat
    var textWidth: CGFloat
    /// Clears the window controls iPadOS draws in the top corner of a windowed app.
    var topInset: CGFloat
    var lineHeight: CGFloat
    var fontSize: CGFloat
    var wordSpacing: CGFloat { fontSize * 0.25 }

    init(size: CGSize) {
        let roomy = size.width > 600
        margin = roomy ? 40 : 14
        textWidth = min(size.width - margin * 2, 620)
        topInset = roomy ? 26 : 0
        lineHeight = (size.height - Self.chrome * 2 - topInset) / Self.linesPerPage
        fontSize = min(textWidth / Self.lineWidthInEm, lineHeight / 1.6)
    }

    /// The text block's left edge: it's centered when the page is wider than a line.
    func textLeft(in size: CGSize) -> CGFloat {
        (size.width - textWidth) / 2
    }

    /// The top of the first line. Pages with fewer than 15 lines (the first two) center them in the text block.
    func linesTop(count: Int) -> CGFloat {
        topInset + Self.chrome + (Self.linesPerPage - CGFloat(count)) * lineHeight / 2
    }
}

/// How the words of a line are spaced, like the printed page: spread to fill the line, or together in the
/// middle on a centered line.
enum AyahLineLayout {
    /// Each word's left edge from the line's left edge, given the words' widths in reading order (right to left).
    /// A word of zero width is a mark that belongs over the word before it (a pause sign in Ghafir 40:77),
    /// so it takes no gap of its own.
    static func lefts(widths: [CGFloat], lineWidth: CGFloat, centered: Bool, wordSpacing: CGFloat) -> [CGFloat] {
        let total = widths.reduce(0, +)
        let gaps = CGFloat(max(widths.filter { $0 > 0 }.count - 1, 0))
        let justified = !centered && gaps > 0
        let spacing = justified ? (lineWidth - total) / gaps : wordSpacing
        var x = (justified ? lineWidth : (lineWidth + total + spacing * gaps) / 2) + spacing
        return widths.map { width in
            if width > 0 { x -= spacing }
            x -= width
            return x
        }
    }
}

/// The soft highlight behind a memorized word: its topic section's color, faint when newly memorized and
/// fuller as the memorization grows strong.
private struct TopicHighlight: Equatable {
    var topic: Int
    var strength: Double

    var color: Color {
        MushafStyle.topic(topic).opacity(0.5 + 0.5 * min(max(strength, 0), 1))
    }

    /// Its size, as fractions of the line height.
    static let height: CGFloat = 0.76
    static let cornerRadius: CGFloat = 0.3
    /// The space left between two sections' highlights on one line, as a fraction of the word spacing.
    static let separation: CGFloat = 0.5
}

/// A word as a line draws it.
private struct LineWord {
    var isAyahEnd: Bool
    /// Its highlight when memorized and topic colors are on.
    var highlight: TopicHighlight?
    var glyph: WordGlyph
}

/// One line of ayat, drawn word by word from the page font's outlines and spaced by `AyahLineLayout`.
private struct AyahLine: View {
    var words: [LineWord]
    var centered: Bool
    var tajweed: Bool
    var wordSpacing: CGFloat

    var body: some View {
        GeometryReader { geometry in
            // Diacritics and markers can reach past the line's box, so the canvas gets room around it.
            let bleed = geometry.size.height
            Canvas { context, _ in
                let height = geometry.size.height
                let lefts = AyahLineLayout.lefts(widths: words.map(\.glyph.size.width), lineWidth: geometry.size.width,
                                                 centered: centered, wordSpacing: wordSpacing).map { $0 + bleed }

                drawHighlights(in: context, lefts: lefts, top: bleed, height: height)

                for (word, left) in zip(words, lefts) {
                    var context = context
                    context.translateBy(x: left, y: bleed + (height - word.glyph.size.height) / 2)
                    if word.isAyahEnd {
                        // A soft oval laid exactly behind the marker's rosette.
                        let box = word.glyph.inkBox
                        context.fill(Path(ellipseIn: box.insetBy(dx: box.width * 0.07, dy: box.height * 0.08)),
                                     with: .color(MushafStyle.markerFill))
                        context.fill(word.glyph.outline, with: .color(MushafStyle.marker))
                    } else {
                        context.fill(word.glyph.outline, with: .color(MushafStyle.ink))
                        if tajweed && !word.glyph.layers.isEmpty {
                            // The colors tint the letters they belong to and nothing outside them.
                            context.clip(to: word.glyph.outline)
                            for layer in word.glyph.layers { context.fill(layer.path, with: .color(layer.color)) }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width + bleed * 2, height: geometry.size.height + bleed * 2)
            .offset(x: -bleed, y: -bleed)
        }
        // The outlines are in left-to-right glyph coordinates; the reading order is laid out above.
        .environment(\.layoutDirection, .leftToRight)
        // Taps go through to the page: the toolbar, or the marking layer in marking mode.
        .allowsHitTesting(false)
    }

    /// Colors each run of memorized words from the same topic section with a soft highlight behind them.
    private func drawHighlights(in context: GraphicsContext, lefts: [CGFloat], top: CGFloat, height: CGFloat) {
        // Runs of consecutive words with the same highlight; a zero-width mark stays with the word before it.
        var runs: [(highlight: TopicHighlight?, first: Int, last: Int)] = []
        for (index, word) in words.enumerated() {
            if let run = runs.last, run.highlight == word.highlight || word.glyph.size.width == 0 {
                runs[runs.count - 1].last = index
            } else {
                runs.append((word.highlight, index, index))
            }
        }
        let edges = runs.map { (right: lefts[$0.first] + words[$0.first].glyph.size.width, left: lefts[$0.last]) }
        // Each highlight reaches a little past its words. Where one section ends and the next begins on a line,
        // the starting section keeps its reach and the ending one gives way, leaving a small space between them.
        let separation = TopicHighlight.separation * wordSpacing
        func startReach(at index: Int) -> CGFloat {
            guard index > 0 else { return wordSpacing }
            return min(wordSpacing, max(edges[index - 1].left - edges[index].right - separation, 0))
        }
        func endReach(at index: Int) -> CGFloat {
            guard index < runs.count - 1 else { return wordSpacing }
            let gap = edges[index].left - edges[index + 1].right
            return min(wordSpacing, max(gap - startReach(at: index + 1) - separation, 0))
        }
        for (index, run) in runs.enumerated() {
            guard let highlight = run.highlight else { continue }
            let right = edges[index].right + startReach(at: index), left = edges[index].left - endReach(at: index)
            let box = CGRect(x: left, y: top + height * (1 - TopicHighlight.height) / 2,
                             width: right - left, height: height * TopicHighlight.height)
            context.fill(Path(roundedRect: box, cornerRadius: height * TopicHighlight.cornerRadius), with: .color(highlight.color))
        }
    }
}
