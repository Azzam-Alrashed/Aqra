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
}

/// Loads the Mushaf fonts straight from the bundle, without registering them system-wide.
@MainActor
enum MushafFonts {
    private static var descriptors: [String: CTFontDescriptor] = [:]
    /// Fonts already made, by path and size, so pages don't create a new font on every render.
    private static var fonts: [String: Font] = [:]

    /// The page's own QCF V2 font, whose glyphs are that page's words.
    static func page(_ number: Int, size: CGFloat) -> Font? {
        font(at: String(format: "qcf2/QCF2%03d.ttf", number), size: size)
    }

    /// The Complex's Hafs Smart font, used for the basmala lines.
    static func hafsSmart(size: CGFloat) -> Font? {
        font(at: "kfgqpc/HafsSmart_08.ttf", size: size)
    }

    /// The surah header font: one glyph draws a surah's whole framed title.
    static func surahHeader(size: CGFloat) -> Font? {
        font(at: "qul/QCF_SurahHeader_COLOR-Regular.ttf", size: size)
    }

    private static func font(at path: String, size: CGFloat) -> Font? {
        let key = "\(path)@\(size)"
        if let cached = fonts[key] { return cached }
        if descriptors[path] == nil,
           let url = MushafStore.resourceURL(path),
           let found = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let first = found.first {
            descriptors[path] = first
        }
        guard let descriptor = descriptors[path] else { return nil }
        let font = Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
        fonts[key] = font
        return font
    }
}

/// One Mushaf page: 15 lines in the page's own font, framed by the surah, juz' and page number.
struct MushafPageView: View {
    var page: MushafPage
    var store: MushafStore

    /// A full Madinah line is about 15.6 em wide in the QCF V2 fonts; leave room for the word gaps.
    private static let lineWidthInEm: CGFloat = 16.4
    /// A surah header glyph is 3.3 em wide.
    private static let headerWidthInEm: CGFloat = 3.303
    private static let linesPerPage: CGFloat = 15

    var body: some View {
        GeometryReader { geometry in
            let roomy = geometry.size.width > 600
            let margin: CGFloat = roomy ? 40 : 14
            let textWidth = min(geometry.size.width - margin * 2, 620)
            let chrome: CGFloat = 30
            // Clears the window controls iPadOS draws in the top corner of a windowed app.
            let topInset: CGFloat = roomy ? 26 : 0
            let lineHeight = (geometry.size.height - chrome * 2 - topInset) / Self.linesPerPage
            let fontSize = min(textWidth / Self.lineWidthInEm, lineHeight / 1.6)

            VStack(spacing: 0) {
                header.frame(height: chrome).padding(.top, topInset)
                VStack(spacing: 0) {
                    ForEach(page.lines, id: \.self) { line in
                        lineView(line, fontSize: fontSize, width: textWidth)
                            .frame(width: textWidth, height: lineHeight)
                    }
                }
                .frame(maxHeight: .infinity)
                footer.frame(height: chrome)
            }
            .padding(.horizontal, margin)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(MushafStyle.paper)
        .environment(\.layoutDirection, .rightToLeft)
        // The words are font glyphs that VoiceOver can't read; give it the page in plain text instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
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
    private func lineView(_ line: MushafLine, fontSize: CGFloat, width: CGFloat) -> some View {
        switch line.kind {
        case .surahName(let surah):
            Text(verbatim: store.surahHeaders[surah] ?? "")
                .font(MushafFonts.surahHeader(size: width * 0.96 / Self.headerWidthInEm))
                .foregroundStyle(MushafStyle.ornament)
                .fixedSize()
        case .basmala:
            Text(verbatim: store.basmala)
                .font(MushafFonts.hafsSmart(size: fontSize * 1.05))
                .foregroundStyle(MushafStyle.ink)
                .fixedSize()
        case .ayah(let words, let centered):
            let font = MushafFonts.page(page.number, size: fontSize)
            if centered {
                HStack(spacing: fontSize * 0.25) {
                    ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                        wordView(word, font: font, fontSize: fontSize)
                    }
                }
            } else {
                // Justified like the printed page: the words spread to fill the line.
                HStack(spacing: 0) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        if index > 0 { Spacer(minLength: 0) }
                        wordView(word, font: font, fontSize: fontSize)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wordView(_ word: MushafWord, font: Font?, fontSize: CGFloat) -> some View {
        if word.isAyahEnd {
            Text(verbatim: word.glyph)
                .font(font)
                .foregroundStyle(MushafStyle.marker)
                .fixedSize()
                .background {
                    Circle()
                        .fill(MushafStyle.markerFill)
                        .frame(width: fontSize * 0.86, height: fontSize * 0.86)
                }
        } else {
            Text(verbatim: word.glyph)
                .font(font)
                .foregroundStyle(MushafStyle.ink)
                .fixedSize()
        }
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
