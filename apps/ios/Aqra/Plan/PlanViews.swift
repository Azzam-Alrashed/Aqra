import SwiftUI

/// How the plan is written across the app.
enum PlanFormat {
    /// «نصف وجه»: a daily amount in the Mushaf's own measure.
    static func amount(_ lines: Int) -> Text {
        switch lines {
        case 4: Text("¼ page")
        case 8: Text("½ page")
        case 11: Text("¾ page")
        case 15: Text("1 page")
        case 19: Text("1¼ pages")
        case 23: Text("1½ pages")
        case 26: Text("1¾ pages")
        case 30: Text("2 pages")
        case 34: Text("2¼ pages")
        case 38: Text("2½ pages")
        default: Text("\(lines) lines")
        }
    }

    /// «الناس ١–٦ · الفلق ١–٥»: a portion's ayat, by surah, in the order they're memorized.
    static func portion(_ ayahs: [Int], store: MushafStore) -> String {
        var groups: [(surah: Int, first: Int, last: Int)] = []
        for ayah in ayahs {
            let reference = store.reference(ofAyah: ayah)
            if let last = groups.last, last.surah == reference.surah, last.last == reference.ayah - 1 {
                groups[groups.count - 1].last = reference.ayah
            } else {
                groups.append((reference.surah, reference.ayah, reference.ayah))
            }
        }
        return groups.map { group in
            let name = store.surahNames[group.surah] ?? ""
            let range = group.first == group.last ? arabic(group.first) : "\(arabic(group.first))–\(arabic(group.last))"
            return "\(name) \(range)"
        }.joined(separator: Separator.arabic)
    }

    /// «رجب ١٤٤٩»: a far date, by the Hijri month.
    static func month(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.month(.wide).year()
        style.calendar = Calendar(identifier: .islamicUmmAlQura)
        return date.formatted(style)
    }

    static func arabic(_ number: Int) -> String {
        number.formatted(.number.locale(Locale(identifier: "ar@numbers=arab")))
    }
}

private typealias Palette = OnboardingPalette
