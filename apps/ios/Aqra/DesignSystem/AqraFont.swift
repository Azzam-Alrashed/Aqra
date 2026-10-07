import CoreText
import SwiftUI

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
