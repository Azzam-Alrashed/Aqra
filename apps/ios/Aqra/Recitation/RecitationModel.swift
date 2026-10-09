import AppleArchive
import Foundation
import System
import WhisperKit

/// The speech model a revision is followed with: Tarteel's Whisper fine-tuned on Quran recitation
/// (`tarteel-ai/whisper-base-ar-quran`, Apache-2.0), converted for Core ML with WhisperKit's tools.
///
/// It's downloaded once, as an Apple Archive of the model folder, kept on the device outside its backups, and run
/// on the device: the student's voice never leaves it and isn't kept.
@MainActor @Observable
final class RecitationModel {
    enum State: Equatable {
        case absent
        case downloading(Double)
        case installing
        case ready
        case failed
    }

    static let shared = RecitationModel()

    /// The version installed; a new one goes in a folder of its own.
    nonisolated static let version = "whisper-base-ar-quran-1"
    /// The archive's size, shown before downloading it.
    nonisolated static let downloadSize: Int64 = 134_001_846
    /// Where the archive is downloaded from (the `AqraRecitationModelURL` Info.plist key; in a debug build, a
    /// `-RecitationModelURL <url>` launch argument comes first).
    static var downloadURL: URL? {
        #if DEBUG
        if let url = UserDefaults.standard.string(forKey: "RecitationModelURL").flatMap(URL.init(string:)) { return url }
        #endif
        return (Bundle.main.object(forInfoDictionaryKey: "AqraRecitationModelURL") as? String).flatMap(URL.init(string:))
    }

    private(set) var state: State = .absent

    /// Application Support/Recitation/<version>
    nonisolated static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Recitation", directoryHint: .isDirectory)
            .appending(path: version, directoryHint: .isDirectory)
    }

    nonisolated static var isInstalled: Bool {
        ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "tokenizer.json"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    /// Whether it can be had at all: installed, or a download is set up.
    var isAvailable: Bool { Self.isInstalled || Self.downloadURL != nil }

    private init() {
        state = Self.isInstalled ? .ready : .absent
    }

    /// Downloads and installs the model, reporting progress in `state`.
    func download() async {
        guard !Self.isInstalled else {
            state = .ready
            return
        }
        guard let url = Self.downloadURL, state != .installing else { return }
        if case .downloading = state { return }
        state = .downloading(0)
        do {
            let progress = DownloadProgress { [weak self] fraction in
                Task { @MainActor in
                    if case .downloading = self?.state { self?.state = .downloading(fraction) }
                }
            }
            let (file, response) = try await URLSession.shared.download(from: url, delegate: progress)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            state = .installing
            try await Task.detached(priority: .userInitiated) { try Self.install(archive: file) }.value
            state = .ready
        } catch {
            state = .failed
        }
    }

    /// Unpacks the archive into a fresh folder, then puts it in place, so a half-installed model is never used.
    nonisolated private static func install(archive: URL) throws {
        let manager = FileManager.default
        let parent = folder.deletingLastPathComponent()
        let staging = parent.appending(path: "\(version).partial", directoryHint: .isDirectory)
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: archive) }
        guard let read = ArchiveByteStream.fileStream(path: FilePath(archive.path), mode: .readOnly, options: [],
                                                      permissions: FilePermissions(rawValue: 0o644)),
              let decompress = ArchiveByteStream.decompressionStream(readingFrom: read),
              let decode = ArchiveStream.decodeStream(readingFrom: decompress),
              let extract = ArchiveStream.extractStream(extractingTo: FilePath(staging.path),
                                                        flags: [.ignoreOperationNotPermitted]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer {
            try? extract.close()
            try? decode.close()
            try? decompress.close()
            try? read.close()
        }
        _ = try ArchiveStream.process(readingFrom: decode, writingTo: extract)
        try? manager.removeItem(at: folder)
        try manager.moveItem(at: staging, to: folder)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = parent
        try? root.setResourceValues(values)
    }

    /// Reports a download's progress as it goes, from the task's own progress (the async download API doesn't
    /// pass the task's write callbacks on).
    private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let report: @Sendable (Double) -> Void
        private let lock = NSLock()
        private var observation: NSKeyValueObservation?

        init(report: @escaping @Sendable (Double) -> Void) {
            self.report = report
        }

        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            let report = report
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                report(min(max(progress.fractionCompleted, 0), 1))
            }
            lock.withLock { self.observation = observation }
        }
    }
}

/// Runs the model: 16 kHz mono audio in, the words it heard out. One stretch at a time.
actor RecitationTranscriber {
    private var kit: WhisperKit?

    /// Loads the model, if it isn't already; this takes a moment the first time on a device, while Core ML
    /// prepares it.
    func load() async throws {
        guard kit == nil else { return }
        let config = WhisperKitConfig(modelFolder: RecitationModel.folder.path, verbose: false, logLevel: .error,
                                      prewarm: true, load: true, download: false)
        kit = try await WhisperKit(config)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let kit else { return "" }
        // Greedy, in Arabic, without timestamps or fallbacks: the stretch is short and the words are compared
        // with the page's, so speed matters more than a second try.
        let options = DecodingOptions(task: .transcribe, language: "ar", temperature: 0, temperatureFallbackCount: 0,
                                      usePrefillPrompt: true, detectLanguage: false, skipSpecialTokens: true,
                                      withoutTimestamps: true, suppressBlank: true,
                                      compressionRatioThreshold: nil, logProbThreshold: nil,
                                      firstTokenLogProbThreshold: nil, noSpeechThreshold: nil)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }

    func unload() async {
        await kit?.unloadModels()
        kit = nil
    }
}
