import Foundation
import Observation

/// What the student has memorized of one ayah.
struct AyahMemory: Codable, Hashable {
    /// How strong it is, from 0 (newly memorized or just declared) to 1; revision will raise it.
    var strength: Double = 0
    /// Whether a teacher has confirmed it in a tasmee'.
    var verified = false
    var since: Date
}

/// The ayat the student has memorized, numbered 0..<6236 in Quran order, kept on the device.
/// It will sync to the student's account once accounts exist.
@MainActor @Observable
final class MemorizationStore {
    private(set) var ayahs: [Int: AyahMemory] = [:]
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// The file the records live in: Application Support/memorization.json.
    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("memorization.json")
    }

    /// Loads the records from `fileURL`, or keeps them in memory only when it's nil (previews and snapshots).
    init(fileURL: URL? = MemorizationStore.defaultURL) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return }
        ayahs = Dictionary(file.ayahs.map { ($0.ayah, $0.memory) }, uniquingKeysWith: { first, _ in first })
    }

    var count: Int { ayahs.count }

    func memory(ofAyah ayah: Int) -> AyahMemory? { ayahs[ayah] }

    func isMemorized(_ ayah: Int) -> Bool { ayahs[ayah] != nil }

    /// How many ayat of a range are memorized.
    func memorizedCount(in range: ClosedRange<Int>) -> Int {
        range.reduce(0) { $0 + (ayahs[$1] == nil ? 0 : 1) }
    }

    func toggle(ayah: Int) {
        mark([ayah], memorized: !isMemorized(ayah))
    }

    /// Marks ayat as memorized (keeping what's already known about them) or as not memorized.
    func mark(_ range: some Sequence<Int>, memorized: Bool) {
        var changed = false
        for ayah in range where (0..<MushafStore.ayahCount).contains(ayah) && isMemorized(ayah) != memorized {
            ayahs[ayah] = memorized ? AyahMemory(since: .now) : nil
            changed = true
        }
        if changed { scheduleSave() }
    }

    // MARK: - Saving

    private struct File: Codable {
        struct Record: Codable {
            var ayah: Int
            var memory: AyahMemory
        }
        var version = 1
        var ayahs: [Record]
    }

    /// Writes shortly after the last change, so marking many ayat at once writes once.
    private func scheduleSave() {
        guard let fileURL else { return }
        pendingSave?.cancel()
        let file = File(ayahs: ayahs.sorted { $0.key < $1.key }.map { File.Record(ayah: $0.key, memory: $0.value) })
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            Self.write(file, to: fileURL)
        }
    }

    /// Writes any change still waiting to be saved, right away.
    func saveNow() {
        guard let fileURL, pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        Self.write(File(ayahs: ayahs.sorted { $0.key < $1.key }.map { File.Record(ayah: $0.key, memory: $0.value) }), to: fileURL)
    }

    private static func write(_ file: File, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(file).write(to: url, options: .atomic)
    }
}

/// The Mushaf's marking mode: a tap marks or unmarks one ayah, and pressing then dragging marks every ayah
/// from where the finger started to where it is (or unmarks them, when the first one was already marked).
@MainActor @Observable
final class MarkingSession {
    let memorization: MemorizationStore
    /// True while the finger is dragging across ayat; the pages don't turn meanwhile.
    private(set) var isPainting = false
    @ObservationIgnored private var anchor: Int?
    @ObservationIgnored private var painting = true
    @ObservationIgnored private var paintEnded = Date.distantPast

    init(memorization: MemorizationStore) {
        self.memorization = memorization
    }

    func tap(_ ayah: Int) {
        // A press that just painted shouldn't also count as a tap.
        guard Date.now.timeIntervalSince(paintEnded) > 0.3 else { return }
        memorization.toggle(ayah: ayah)
    }

    func paint(_ ayah: Int) {
        if anchor == nil {
            anchor = ayah
            painting = !memorization.isMemorized(ayah)
            isPainting = true
        }
        guard let anchor else { return }
        memorization.mark(min(anchor, ayah)...max(anchor, ayah), memorized: painting)
    }

    func endPaint() {
        anchor = nil
        isPainting = false
        paintEnded = .now
    }

    /// Marks every ayah of the given pages, or unmarks them when they're all already marked.
    func toggle(_ ayahs: ClosedRange<Int>) {
        memorization.mark(ayahs, memorized: memorization.memorizedCount(in: ayahs) < ayahs.count)
    }
}
