import Foundation
import Testing
@testable import Aqra

/// Every string the app shows has its Arabic, and every count reads right in both languages.
struct LocalizationTests {
    /// Arabic has six plural forms, and each one is needed: «يوم واحد، يومان، ٣ أيام، ١١ يومًا، ١٠٠ يوم، ٠ أيام».
    private static let arabicForms: Set<String> = ["zero", "one", "two", "few", "many", "other"]
    private static let englishForms: Set<String> = ["one", "other"]

    /// The catalog as it is in the repo; the build compiles it into the app's strings files.
    private static func catalog() throws -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Aqra/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try #require(json?["strings"] as? [String: [String: Any]])
    }

    private static func localization(_ entry: [String: Any], _ language: String) -> [String: Any]? {
        (entry["localizations"] as? [String: Any])?[language] as? [String: Any]
    }

    private static func pluralForms(_ localization: [String: Any]?) -> [String: String]? {
        guard let plural = (localization?["variations"] as? [String: Any])?["plural"] as? [String: Any] else { return nil }
        return plural.compactMapValues { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }
    }

    private static func value(_ localization: [String: Any]?) -> String? {
        (localization?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    /// The format specifiers in a string, by kind, in order of their position (%1$@ before %2$lld).
    private static func specifiers(_ text: String) -> [String] {
        let pattern = /%(?:(\d+)\$)?(lld|ld|d|@|f|\.\d+f)/
        var found: [(Int, String)] = []
        for (index, match) in text.matches(of: pattern).enumerated() {
            let position = match.output.1.flatMap { Int($0) } ?? index + 1
            found.append((position, match.output.2 == "@" ? "@" : "number"))
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    @Test func everyKeyHasArabic() throws {
        var missing: [String] = []
        for (key, entry) in try Self.catalog() where !key.isEmpty && entry["shouldTranslate"] as? Bool != false {
            let arabic = Self.localization(entry, "ar")
            let text = Self.value(arabic)
            let hasText = text.map { !$0.isEmpty } ?? false
            let hasForms = !(Self.pluralForms(arabic) ?? [:]).isEmpty || arabic?["substitutions"] != nil
            if !hasText && !hasForms { missing.append(key) }
        }
        #expect(missing.isEmpty, "No Arabic for: \(missing.sorted())")
    }

    @Test func everyCountHasAllItsPluralForms() throws {
        var incomplete: [String] = []
        for (key, entry) in try Self.catalog() {
            let arabic = Self.localization(entry, "ar"), english = Self.localization(entry, "en")
            if let forms = Self.pluralForms(arabic), Set(forms.keys) != Self.arabicForms {
                incomplete.append("\(key) (ar: \(forms.keys.sorted()))")
            }
            if let forms = Self.pluralForms(english), !Self.englishForms.isSubset(of: forms.keys) {
                incomplete.append("\(key) (en: \(forms.keys.sorted()))")
            }
            // A count that English varies must vary in Arabic too, or Arabic reads «٣ صفحة».
            if Self.pluralForms(english) != nil && Self.pluralForms(arabic) == nil && arabic?["substitutions"] == nil {
                incomplete.append("\(key) (ar has no plural forms)")
            }
            for (name, substitution) in (arabic?["substitutions"] as? [String: Any]) ?? [:] {
                let forms = ((substitution as? [String: Any])?["variations"] as? [String: Any])?["plural"] as? [String: Any]
                if Set(forms?.keys.map { $0 } ?? []) != Self.arabicForms { incomplete.append("\(key) (ar substitution \(name))") }
            }
        }
        #expect(incomplete.isEmpty, "Incomplete plural forms: \(incomplete.sorted())")
    }

    /// The Arabic takes the same values as the English, in kind: a name where the key has a name, a number where it
    /// has a number. A plural's one, two and zero forms may spell the number out («يومان»).
    @Test func arabicKeepsTheKeysValues() throws {
        var mismatched: [String] = []
        for (key, entry) in try Self.catalog() {
            let expected = Self.specifiers(key)
            let arabic = Self.localization(entry, "ar")
            if let text = Self.value(arabic), arabic?["substitutions"] == nil, Self.specifiers(text) != expected {
                mismatched.append("\(key) → \(text)")
            }
            for (form, text) in Self.pluralForms(arabic) ?? [:] where !["zero", "one", "two"].contains(form) {
                if Self.specifiers(text) != expected { mismatched.append("\(key) [\(form)] → \(text)") }
            }
        }
        #expect(mismatched.isEmpty, "Values that don't match their key: \(mismatched.sorted())")
    }

    // MARK: - As built into the app

    private static func arabicBundle() throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: "ar", ofType: "lproj"), "the app has no Arabic")
        return try #require(Bundle(path: path))
    }

    private static func arabic(_ key: String, _ count: Int) throws -> String {
        let format = try arabicBundle().localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: Locale(identifier: "ar"), count)
    }

    /// The days of a streak count up in their own forms: never «١ أيام» (onboarding page 3 showed it).
    @Test func daysCountInArabic() throws {
        #expect(try Self.arabic("%lld days", 1) == "يوم واحد")
        #expect(try Self.arabic("%lld days", 2) == "يومان")
        #expect(try Self.arabic("%lld days", 3).contains("أيام"))
        #expect(try Self.arabic("%lld days", 11).contains("يومًا"))
    }

    /// A preposition or a verb's object takes the dual's genitive or accusative.
    @Test func arabicGrammarAfterVerbsAndPrepositions() throws {
        #expect(try Self.arabic("Complete the wird on %lld days", 2) == "أتمّ الوِرد في يومين")
        #expect(try Self.arabic("Memorize %lld lines", 1) == "احفظ سطرًا واحدًا")
        #expect(try Self.arabic("Memorize %lld lines", 2) == "احفظ سطرين")
        #expect(try Self.arabic("You need %lld more credits.", 2) == "تحتاج عملتين أُخريين.")
    }

    /// The revision's X says what it does, in both languages.
    @Test func leavingARevisionSaysThePageIsntRecorded() throws {
        let english = try #require(Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        #expect(english.localizedString(forKey: "Leave revision", value: nil, table: nil) == "Leave without recording this page")
        #expect(try Self.arabicBundle().localizedString(forKey: "Leave revision", value: nil, table: nil)
                == "الخروج دون تسجيل مراجعة هذه الصفحة")
    }
}
