import SwiftUI

/// The منازل: ten steps rising toward a gold star, each worth three juz' of memorization, in the colored-Mushaf
/// bands of the onboarding stairs (butter, peach, rose, lavender, sky, two steps each). `GlossyStairs` draws them.
enum ManazilStairs {
    nonisolated static let stepCount = 10
    nonisolated static let juzPerStep = 3

    /// A juz's band colors: six juz' (two steps) per band, bottom to top.
    @MainActor static func face(forJuz juz: Int) -> (top: Color, bottom: Color) {
        let face = AqraLogoMark.faces[min(max(juz - 1, 0) / 6, AqraLogoMark.faces.count - 1)]
        return (Color(light: face.top, dark: face.top), Color(light: face.bottom, dark: face.bottom))
    }
}
