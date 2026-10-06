import CoreText
import SwiftUI

/// Typography layers: the Mushaf's Uthmani font is for the Quran only,
/// Amiri is for quoted sacred text such as hadith, and the system font is the app's own voice.
enum AqraFont {
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    static func hadith(size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Amiri-Bold" : "Amiri-Regular", size: size, relativeTo: .title3)
    }
}
