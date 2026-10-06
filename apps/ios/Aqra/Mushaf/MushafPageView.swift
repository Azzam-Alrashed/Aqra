import CoreText
import SwiftUI

/// The Mushaf's look: warm paper, dark ink, and gold-trimmed surah headers.
enum MushafStyle {
    static let paper = Color(light: 0xFBF7EE, dark: 0xFBF7EE)
    static let ink = Color(light: 0x1C1712, dark: 0x1C1712)
    static let chrome = Color(light: 0x8A7A64, dark: 0x8A7A64)
    static let headerFill = Color(light: 0xF4EAD5, dark: 0xF4EAD5)
    static let gold = Color(light: 0xC9A24A, dark: 0xC9A24A)
}

/// Loads the Mushaf fonts straight from the bundle, without registering them system-wide.
@MainActor
enum MushafFonts {
    private static var descriptors: [String: CTFontDescriptor] = [:]

    /// The page's own QCF V2 font, whose glyphs are that page's words.
    static func page(_ number: Int, size: CGFloat) -> Font? {
        font(at: String(format: "qcf2/QCF2%03d.ttf", number), size: size)
    }

    /// The Complex's Hafs Smart font, used for the basmala lines.
    static func hafsSmart(size: CGFloat) -> Font? {
        font(at: "kfgqpc/HafsSmart_08.ttf", size: size)
    }

    private static func font(at path: String, size: CGFloat) -> Font? {
        if descriptors[path] == nil,
           let url = MushafStore.resourceURL(path),
           let found = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let first = found.first {
            descriptors[path] = first
        }
        guard let descriptor = descriptors[path] else { return nil }
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}

/// One Mushaf page: 15 lines in the page's own font, framed by the surah, juz' and page number.
struct MushafPageView: View {
    var page: MushafPage
    var store: MushafStore

    /// A full Madinah line is about 15.6 em wide in the QCF V2 fonts; leave room for the word gaps.
    private static let lineWidthInEm: CGFloat = 16.4
    private static let linesPerPage: CGFloat = 15

    var body: some View {
        GeometryReader { geometry in
            let margin: CGFloat = geometry.size.width > 600 ? 40 : 14
            let textWidth = min(geometry.size.width - margin * 2, 620)
            let chrome: CGFloat = 30
            let lineHeight = (geometry.size.height - chrome * 2) / Self.linesPerPage
            let fontSize = min(textWidth / Self.lineWidthInEm, lineHeight / 1.6)

            VStack(spacing: 0) {
                header.frame(height: chrome)
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
    }

    @ViewBuilder
    private func lineView(_ line: MushafLine, fontSize: CGFloat, width: CGFloat) -> some View {
        switch line.kind {
        case .surahName(let surah):
            SurahHeader(name: store.surahNames[surah] ?? "", width: width * 0.86, fontSize: fontSize)
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
                        Text(verbatim: word).font(font).fixedSize()
                    }
                }
                .foregroundStyle(MushafStyle.ink)
            } else {
                // Justified like the printed page: the words spread to fill the line.
                HStack(spacing: 0) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        if index > 0 { Spacer(minLength: 0) }
                        Text(verbatim: word).font(font).fixedSize()
                    }
                }
                .foregroundStyle(MushafStyle.ink)
            }
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

/// A surah title inside a gold-trimmed band.
private struct SurahHeader: View {
    var name: String
    var width: CGFloat
    var fontSize: CGFloat

    var body: some View {
        Text(verbatim: "سورة \(name)")
            .font(AqraFont.hadith(size: fontSize * 0.95, bold: true))
            .fontDesign(nil)
            .foregroundStyle(MushafStyle.ink)
            .frame(width: width, height: fontSize * 1.55)
            .background(MushafStyle.headerFill, in: RoundedRectangle(cornerRadius: fontSize * 0.4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: fontSize * 0.4, style: .continuous)
                    .strokeBorder(MushafStyle.gold, lineWidth: 1.5)
                    .padding(2)
            }
    }
}
