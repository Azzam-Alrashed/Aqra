import Foundation

/// Follows a recitation through the words of a page: how far the student has reached, which ayat they stumbled on
/// and how, and the words a long pause brought them (the prompt, تلقين).
///
/// It's given what the model heard, a stretch at a time, and places it among the words expected — a little before
/// where the student is (going back to correct) to well after it (skipping). It never decides what the words are:
/// the page's own words are the only ones shown.
struct RecitationTracker {
    struct Word: Hashable {
        /// The ayah, numbered 0..<6236, and the word's place in it (from 1), as the Mushaf numbers them.
        var ayah: Int
        var position: Int
        /// The word as recited, normalized (see `RecitationText`).
        var text: String
    }

    let words: [Word]
    /// The next word expected: every word before it was heard, prompted or passed over.
    private(set) var cursor = 0
    /// How far the stretch still being recited reaches, before it's settled.
    private(set) var tentative = 0
    private(set) var stumbles: [Int: Set<MistakeType>] = [:]
    /// The words shown as prompts, by their index in `words`.
    private(set) var prompted: Set<Int> = []

    /// Going back this many words or fewer to start again after a breath is reciting as it should be (الابتداء بما
    /// قبله); further back is going back to correct.
    var allowedRestart = 3

    init(words: [Word]) {
        self.words = words
    }

    /// How many words, from the first, are revealed.
    var reached: Int { max(cursor, tentative) }

    var isComplete: Bool { cursor >= words.count }

    /// Whether the student is inside an ayah rather than between two.
    var isMidAyah: Bool {
        cursor > 0 && cursor < words.count && words[cursor].ayah == words[cursor - 1].ayah
    }

    /// What the model heard. A stretch still being recited (`final` false) only reveals the words it reaches; once
    /// the student pauses, the whole stretch is settled: skipped words, wrong words and going back are stumbles.
    mutating func hear(_ text: String, final: Bool) {
        let heard = withoutOpening(RecitationText.normalizedWords(text))
        // A fragment of a letter or two (a word cut by a breath) says nothing either way.
        guard !heard.isEmpty, !(heard.count == 1 && heard[0].count <= 2) else {
            if final { tentative = cursor }
            return
        }
        let matches = Self.align(heard, to: words.map(\.text), near: cursor)
        let matchedHeard = matches.reduce(0) { $0 + $1.heard.count }
        guard let first = matches.first?.expected.lowerBound, let last = matches.last?.expected.upperBound,
              matchedHeard >= max(1, (heard.count + 1) / 2) else {
            // Little of it fits anywhere near: words that aren't the page's.
            if final {
                if cursor < words.count { stumble(words[cursor].ayah, .memorization) }
                tentative = cursor
            }
            return
        }
        guard final else {
            // Revealed only when it carries on from where the student is.
            if first <= cursor { tentative = max(tentative, last) }
            return
        }
        if first < cursor - allowedRestart {
            stumble(words[first].ayah, .hesitation)
        } else if first > cursor {
            for index in cursor..<first { stumble(words[index].ayah, .memorization) }
        }
        // Inside the stretch: words expected but not heard, and words heard that fit nowhere.
        let matched = Set(matches.flatMap { Array($0.expected) })
        for index in max(first, cursor)..<max(last, max(first, cursor)) where !matched.contains(index) {
            stumble(words[index].ayah, .memorization)
        }
        if heard.count - matchedHeard >= 2 { stumble(words[last - 1].ayah, .memorization) }
        cursor = max(cursor, last)
        tentative = cursor
    }

    /// A long pause: the next word is shown, and its ayah needed prompting.
    mutating func prompt() {
        guard cursor < words.count else { return }
        prompted.insert(cursor)
        stumble(words[cursor].ayah, .prompting)
        cursor += 1
        tentative = cursor
    }

    /// A long pause inside an ayah that passed without a prompt (the student carried on by themselves before one
    /// could be shown): a hesitation on that ayah.
    mutating func hesitated() {
        guard isMidAyah else { return }
        stumble(words[cursor].ayah, .hesitation)
    }

    /// The student revealed words by hand: carry on from there, without counting them.
    mutating func skip(to index: Int) {
        cursor = min(max(cursor, index), words.count)
        tentative = max(tentative, cursor)
    }

    /// The isti'adha and the basmala a reciter says before reciting, or at the start of a surah, aren't words of
    /// the page — unless the basmala is (al-Fatiha's first ayah).
    private func withoutOpening(_ heard: [String]) -> [String] {
        var heard = heard[...]
        let expected = words[min(cursor, words.count)...].prefix(4).map(\.text)
        for opening in [Self.istiadha, Self.basmala] where opening != expected {
            if heard.count >= opening.count,
               zip(heard.prefix(opening.count), opening).allSatisfy({ RecitationText.similarity($0, $1) >= 0.75 }) {
                heard = heard.dropFirst(opening.count)
            }
        }
        return Array(heard)
    }

    private static let istiadha = ["اعوذ", "بالله", "من", "الشيطان", "الرجيم"]
    private static let basmala = ["بسم", "الله", "الرحمن", "الرحيم"]

    private mutating func stumble(_ ayah: Int, _ type: MistakeType) {
        stumbles[ayah, default: []].insert(type)
    }

    // MARK: - Alignment

    /// Where heard words fit among the expected ones, searched from a little before `cursor` to well after it.
    /// Every heard word is placed, matched or left over; the expected words around them are free to skip. Exact
    /// matches beat near ones and long words short ones, two heard words may make one expected word or one heard
    /// word two (the model and the Mushaf don't always split words alike), and starting ahead of the cursor, or
    /// skipping words inside the run, costs more than going back a little.
    /// Returns the matched runs in order.
    static func align(_ heard: [String], to expected: [String], near cursor: Int, back: Int = 12, ahead: Int = 40)
        -> [(heard: Range<Int>, expected: Range<Int>)] {
        let low = max(0, min(cursor, expected.count) - back), high = min(expected.count, cursor + ahead)
        let window = Array(expected[low..<high])
        let n = heard.count, m = window.count
        guard n > 0, m > 0 else { return [] }

        func score(_ a: String, _ b: String) -> Double? {
            // A short word says less about where the student is than a long one: «في» is on every page.
            let shorter = min(a.unicodeScalars.count, b.unicodeScalars.count)
            let weight = 0.5 + 0.125 * Double(min(shorter, 4))
            if a == b { return 2 * weight }
            // Short words must be closer: «أيكم» isn't «إياك».
            let needed = shorter <= 4 ? 0.85 : 0.75
            return RecitationText.similarity(a, b) >= needed ? 1.4 * weight : nil
        }
        enum Step { case start, skipHeard, skipExpected, match, mismatch, joinHeard, joinExpected }
        var best = [[Double]](repeating: [Double](repeating: -.infinity, count: m + 1), count: n + 1)
        var step = [[Step]](repeating: [Step](repeating: .start, count: m + 1), count: n + 1)
        // Starting ahead of the student says words were skipped, so it costs more than going back a little.
        for j in 0...m {
            let start = low + j
            best[0][j] = start < cursor ? -0.05 * Double(cursor - start) : -0.5 * Double(start - cursor)
        }
        for i in 1...n {
            for j in 0...m {
                var value = best[i - 1][j] - 1, how = Step.skipHeard
                func consider(_ candidate: Double, _ move: Step) {
                    if candidate > value { value = candidate; how = move }
                }
                if j > 0 {
                    consider(best[i][j - 1] - 1.5, .skipExpected)
                    if let s = score(heard[i - 1], window[j - 1]) {
                        consider(best[i - 1][j - 1] + s, .match)
                    } else {
                        consider(best[i - 1][j - 1] - 1, .mismatch)
                    }
                    if i > 1, let s = score(heard[i - 2] + heard[i - 1], window[j - 1]) {
                        consider(best[i - 2][j - 1] + s - 0.2, .joinHeard)
                    }
                    if j > 1, let s = score(heard[i - 1], window[j - 2] + window[j - 1]) {
                        consider(best[i - 1][j - 2] + s - 0.2, .joinExpected)
                    }
                }
                best[i][j] = value
                step[i][j] = how
            }
        }
        var j = (0...m).max { best[n][$0] < best[n][$1] } ?? 0
        var i = n
        var runs: [(heard: Range<Int>, expected: Range<Int>)] = []
        while i > 0 {
            switch step[i][j] {
            case .skipHeard: i -= 1
            case .skipExpected: j -= 1
            case .mismatch: i -= 1; j -= 1
            case .match:
                runs.append((i - 1..<i, low + j - 1..<low + j)); i -= 1; j -= 1
            case .joinHeard:
                runs.append((i - 2..<i, low + j - 1..<low + j)); i -= 2; j -= 1
            case .joinExpected:
                runs.append((i - 1..<i, low + j - 2..<low + j)); i -= 1; j -= 2
            case .start: i = 0
            }
        }
        return runs.reversed()
    }
}

extension RecitationTracker {
    /// Following the revision of a page: the words of the ayat it covers, as far as they're on this page (an ayah
    /// can begin on the page before or end on the next), in reading order.
    init(page: MushafPage, ayahs: [Int], store: MushafStore) {
        let covered = Set(ayahs)
        var spoken: [Int: [String]] = [:]
        var words: [Word] = []
        for line in page.lines {
            guard case .ayah(let lineWords, _) = line.kind else { continue }
            for word in lineWords where !word.isAyahEnd && covered.contains(word.ayah) {
                if spoken[word.ayah] == nil {
                    spoken[word.ayah] = RecitationText.words(ofAyah: store.ayahPlainTexts[word.ayah],
                                                             mushafWords: store.ayahWordCounts[word.ayah])
                }
                let texts = spoken[word.ayah] ?? []
                guard texts.indices.contains(word.position - 1) else { continue }
                words.append(Word(ayah: word.ayah, position: word.position, text: texts[word.position - 1]))
            }
        }
        self.init(words: words)
    }
}
