import CryptoKit
import Foundation
import Testing
@testable import Aqra

/// Guards the sacred texts against any change, however small.
struct SacredTextTests {
    private func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 of the hadith as published on https://dorar.net/hadith/sharh/116139
    @Test func hadithMatchesSource() {
        #expect(sha256(SacredText.reciteAndAscend) == "603fc0da4a3d989fe2dfed4176da0fd60748accc83eb908c12bc8fee5ae77681")
    }

    /// SHA-256 of the translation as published on https://sunnah.com/tirmidhi:2914
    @Test func translationMatchesSource() {
        #expect(sha256(SacredText.reciteAndAscendTranslation) == "480209807cfb072ed78d8cca9a7bc32c481cb53e97d2b08e511c493bb084115c")
    }

    @Test func emphasisIsPartOfHadith() {
        #expect(SacredText.reciteAndAscend.contains(SacredText.reciteAndAscendEmphasis))
    }
}
