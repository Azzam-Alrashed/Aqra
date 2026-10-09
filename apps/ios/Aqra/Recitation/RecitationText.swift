import Foundation

/// What a student says when reciting an ayah, taken from the Complex's official Imla'i text and matched to the words
/// of the Mushaf. It's only used to follow a recitation; the page always shows the Mushaf's own words.
enum RecitationText {
    /// Plain words the Mushaf writes joined to the word after them: «أو لا» is «أَوَلَا», «ها أنتم» is «هَٰٓأَنتُمْ»,
    /// «إل ياسين» is «إِلۡيَاسِينَ». Only where the ayah's word count says so: «أو» on its own stays a word.
    private static let joining: Set<String> = ["أو", "ها", "إل"]

    /// One normalized word for each word of the Mushaf in an ayah (`mushafWords` of them, the ayah-end marker left
    /// out), in order.
    static func words(ofAyah plain: String, mushafWords: Int) -> [String] {
        let tokens = plain.unicodeScalars.filter { $0 != "\u{200E}" && $0 != "\u{200F}" }
            .split(separator: " ").map { String(String.UnicodeScalarView($0)) }
        let excess = tokens.count - mushafWords
        var joined = Set<Int>()
        if excess > 0 {
            var candidates = tokens.indices.dropLast().filter { joining.contains(tokens[$0]) }
            if candidates.count > excess {
                // Where it's ambiguous (al-A'raf 7:88, at-Tawbah 9:126) the Mushaf joins «أو» to a short particle
                // («أَوَلَوۡ», «أَوَلَا»), not to the longer word after another «أو».
                let short = candidates.filter { tokens[$0 + 1].count <= 2 }
                if short.count >= excess { candidates = short }
            }
            joined = Set(candidates.prefix(excess))
        }
        var words: [String] = []
        var pending = ""
        for (index, token) in tokens.enumerated() {
            pending += normalize(token)
            if !joined.contains(index) {
                words.append(pending)
                pending = ""
            }
        }
        return words
    }

    /// Recited text as normalized words: what the model heard, ready to compare with the ayat.
    static func normalizedWords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map { normalize(String($0)) }.filter { !$0.isEmpty }
    }

    /// A word without tashkeel, Quranic marks or tatweel, with one form of alef, ya for alef maqsura, ha for ta
    /// marbuta and the seated hamzas on their seat, and nothing that isn't an Arabic letter.
    static func normalize(_ word: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x0610...0x061A, 0x064B...0x065F, 0x0670, 0x06D6...0x06ED, 0x0640:
                continue
            case 0x0622, 0x0623, 0x0625, 0x0671: scalars.append("\u{0627}")
            case 0x0649, 0x0626: scalars.append("\u{064A}")
            case 0x0629: scalars.append("\u{0647}")
            case 0x0624: scalars.append("\u{0648}")
            case 0x0621...0x064A: scalars.append(scalar)
            default: continue
            }
        }
        return String(scalars)
    }

    /// How alike two normalized words are, from 0 to 1: the share of their letters left after the fewest edits.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let a = Array(a.unicodeScalars), b = Array(b.unicodeScalars)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        let total = Double(a.count + b.count)
        return (total - Double(previous[b.count])) / total
    }
}
