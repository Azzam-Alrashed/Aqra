import CoreText
import SwiftUI
import UIKit

/// Typography layers: the Mushaf's Uthmani font is for the Quran only,
/// Amiri is for quoted sacred text such as hadith, and the system font is the app's own voice.
enum AqraFont {
    /// Registers Amiri, and the Mushaf's two text fonts (the surah headers and the basmala) with the font
    /// manager, so that a `Font` made from them resolves when the text is drawn rather than falling back to
    /// the system font. The 604 page fonts aren't registered: their words are drawn from outlines.
    static func registerBundledFonts() {
        let urls = ["", "quran/qul", "quran/kfgqpc"].flatMap {
            Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: $0.isEmpty ? nil : $0) ?? []
        }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    static func hadith(size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Amiri-Bold" : "Amiri-Regular", size: size, relativeTo: .title3)
    }
}

extension View {
    /// The app's own voice in the system font, at a size that follows the reader's text size (Dynamic Type): the
    /// design's size at the default setting, scaled as iOS scales the text style nearest it. The app caps the growth
    /// at Accessibility 2 (see `AqraApp`). Composed pictures (the stairs, floating chips, tiles) and the Mushaf's own
    /// chrome keep fixed sizes with `.font(.system(size:))`.
    func aqraFont(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil, monospacedDigit: Bool = false) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, monospacedDigit: monospacedDigit))
    }
}

private struct ScaledFont: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight?
    var design: Font.Design?
    var monospacedDigit: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let scaled = UIFontMetrics(forTextStyle: Self.style(near: size)).scaledValue(for: size, compatibleWith: traits)
        let font = Font.system(size: scaled, weight: weight, design: design)
        return content.font(monospacedDigit ? font.monospacedDigit() : font)
    }

    /// The text style whose default size is nearest, whose growth curve the size follows.
    private static func style(near size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption1
        case ..<14: .footnote
        case ..<15.5: .subheadline
        case ..<17.5: .body
        case ..<21: .title3
        case ..<25: .title2
        case ..<31: .title1
        default: .largeTitle
        }
    }
}

/// What separates two facts on one line. English uses a middle dot; Arabic uses its comma, because a middle dot
/// beside Arabic-Indic digits reads as a zero: «٣ · ٤» looks like «٣٠٤».
enum Separator {
    /// Between two facts in the app's language, with its spaces: " · ", or "، " in Arabic.
    static var facts: String {
        String(localized: "fact separator", defaultValue: " · ", comment: "Between two facts on one line, with its spaces. Arabic uses its comma: a middle dot beside Arabic-Indic digits reads as a zero.")
    }

    /// Between two facts in a line that's always Arabic (the Mushaf's own lines, portions, pages heard).
    static let arabic = "، "
}
