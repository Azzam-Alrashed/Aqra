import AppleArchive
import CryptoKit
import Foundation
import os
import System
import WhisperKit

/// The speech model a revision is followed with: Tarteel's Whisper fine-tuned on Quran recitation
/// (`tarteel-ai/whisper-base-ar-quran`, Apache-2.0), converted for Core ML with WhisperKit's tools.
///
/// It's downloaded once, as an Apple Archive of the model folder, kept on the device outside its backups, and run
/// on the device: the student's voice never leaves it and isn't kept. The download goes on in the background and
/// carries on where it stopped; the archive is checked against its checksum before it's unpacked; a model that isn't
/// whole isn't installed.
@MainActor @Observable
final class RecitationModel {
    enum State: Equatable {
        case absent
        case downloading(Double)
        case installing
        case ready
        case failed(Failure)
    }

    /// Why the model isn't on the device.
    enum Failure: Equatable {
        /// There isn't room for the archive and the unpacked model.
        case space
        /// The download didn't finish; it carries on from where it stopped next time.
        case download
        /// The archive didn't match its checksum, or didn't hold the model.
        case corrupt
    }

    /// What went wrong between the download and the install.
    enum ModelError: Error, Equatable {
        /// The archive isn't the one published: its SHA-256 doesn't match.
        case checksum
        /// The archive couldn't be unpacked, or doesn't hold the whole model.
        case incomplete
    }

    static let shared = RecitationModel()

    /// The version installed; a new one goes in a folder of its own.
    nonisolated static let version = "whisper-base-ar-quran-1"
    /// The archive's size, shown before downloading it.
    nonisolated static let downloadSize: Int64 = 134_001_846
    /// The archive's SHA-256 (backend/README.md): a download that doesn't match isn't installed.
    nonisolated static let checksum = "fd456db6f635bb49a17e4df535e70505ffd03094e9eccc00c3a6f75f8115c686"
    /// What the unpacked model takes on the device (measured: 145,292 KiB), for the free-space check.
    nonisolated static let installedSize: Int64 = 149_000_000
    /// Room to spare beyond the archive and the model.
    nonisolated static let spareSpace: Int64 = 50_000_000
    /// The background session's name; the system relaunches the app for it (see `AqraAppDelegate`).
    nonisolated static let sessionIdentifier = "com.azzamalrashed.aqra.recitation-model"
    /// Where the archive is downloaded from (the `AqraRecitationModelURL` Info.plist key; in a debug build, a
    /// `-RecitationModelURL <url>` launch argument comes first).
    static var downloadURL: URL? {
        #if DEBUG
        if let url = UserDefaults.standard.string(forKey: "RecitationModelURL").flatMap(URL.init(string:)) { return url }
        #endif
        return (Bundle.main.object(forInfoDictionaryKey: "AqraRecitationModelURL") as? String).flatMap(URL.init(string:))
    }

    private(set) var state: State = .absent

    /// Application Support/Recitation: the versions, the archive while it's downloaded, and what a stopped download
    /// left to carry on from.
    nonisolated static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Recitation", directoryHint: .isDirectory)
    }
    /// Application Support/Recitation/<version>
    nonisolated static var folder: URL { root.appending(path: version, directoryHint: .isDirectory) }
    /// The archive, downloaded and not yet unpacked.
    nonisolated static var archive: URL { root.appending(path: "\(version).aar") }
    /// What a download that stopped left behind, to carry on from.
    nonisolated static var resumeData: URL { root.appending(path: "\(version).resume") }

    nonisolated static var isInstalled: Bool { isInstalled(at: folder) }

    /// Whether a model folder is whole: every file it runs from is there.
    nonisolated static func isInstalled(at folder: URL) -> Bool {
        ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "tokenizer.json"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    /// Whether it can be had at all: installed, or a download is set up.
    var isAvailable: Bool { Self.isInstalled || Self.downloadURL != nil }

    /// The space a download needs: the archive, the unpacked model, and room to spare.
    nonisolated static var requiredSpace: Int64 { downloadSize + installedSize + spareSpace }

    nonisolated static func freeSpace() -> Int64 {
        let values = try? URL.applicationSupportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    }

    @ObservationIgnored private let downloader = Downloader()
    /// A background session: the download goes on while the app is in the background, and what a stopped download
    /// left is kept to carry on from.
    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: downloader, delegateQueue: nil)
    }()
    /// The system's completion handler for the background session's events, when it relaunched the app for them.
    static var backgroundEventsHandled: (() -> Void)?

    private init() {
        // Before the session can hand over a finished download: nothing is being installed yet.
        Self.cleanUp()
        state = Self.isInstalled ? .ready : .absent
        downloader.model = self
        if !Self.isInstalled { reconnect() }
    }

    /// Picks up a download the background session carried on with while the app was away.
    private func reconnect() {
        session.getAllTasks { [weak self] tasks in
            guard let task = tasks.first(where: { $0 is URLSessionDownloadTask }) else { return }
            let expected = task.countOfBytesExpectedToReceive > 0 ? task.countOfBytesExpectedToReceive : Self.downloadSize
            let fraction = min(max(Double(task.countOfBytesReceived) / Double(expected), 0), 1)
            Task { @MainActor in
                guard let self, self.state == .absent else { return }
                self.state = .downloading(fraction)
            }
        }
    }

    /// Downloads and installs the model, reporting progress in `state`. A download that stopped carries on from
    /// where it was.
    func download() {
        guard !Self.isInstalled else {
            state = .ready
            return
        }
        guard let url = Self.downloadURL else { return }
        switch state {
        case .downloading, .installing: return
        default: break
        }
        guard Self.freeSpace() >= Self.requiredSpace else {
            state = .failed(.space)
            return
        }
        state = .downloading(0)
        let task: URLSessionDownloadTask
        if let data = try? Data(contentsOf: Self.resumeData), !data.isEmpty {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: url)
        }
        task.resume()
    }

    // MARK: - What the downloader reports

    fileprivate func progressed(_ fraction: Double) {
        if case .downloading = state { state = .downloading(fraction) }
    }

    /// The archive is in place (or couldn't be moved there): check it and unpack it.
    fileprivate func downloaded(moved: Bool, status: Int?) {
        try? FileManager.default.removeItem(at: Self.resumeData)
        guard moved, status == nil || status == 200 || status == 206 else {
            try? FileManager.default.removeItem(at: Self.archive)
            state = .failed(.download)
            return
        }
        state = .installing
        Task.detached(priority: .userInitiated) {
            let outcome = Result { try Self.verifyAndInstall(archive: Self.archive, expecting: Self.checksum, into: Self.folder) }
            await MainActor.run { RecitationModel.shared.installed(outcome) }
        }
    }

    private func installed(_ outcome: Result<Void, any Error>) {
        switch outcome {
        case .success:
            state = Self.isInstalled ? .ready : .failed(.corrupt)
        case .failure(let error):
            state = .failed(error is ModelError ? .corrupt : .download)
        }
    }

    /// The download stopped: what it left is kept to carry on from, and when it left nothing (or what it carried on
    /// from no longer works), the next try starts afresh.
    fileprivate func failed(resumeData: Data?) {
        if let resumeData {
            try? FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
            try? resumeData.write(to: Self.resumeData, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: Self.resumeData)
        }
        if case .downloading = state { state = .failed(.download) }
    }

    // MARK: - Checking, unpacking, cleaning up

    /// Checks the archive against its checksum and unpacks it into a fresh folder, then puts it in place, so a
    /// half-installed model is never used; a model that isn't whole is removed again. The archive is removed either
    /// way.
    nonisolated static func verifyAndInstall(archive: URL, expecting checksum: String, into folder: URL) throws {
        defer { try? FileManager.default.removeItem(at: archive) }
        guard try sha256(of: archive) == checksum else { throw ModelError.checksum }
        do {
            try install(archive: archive, into: folder)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw ModelError.incomplete
        }
        guard isInstalled(at: folder) else {
            try? FileManager.default.removeItem(at: folder)
            throw ModelError.incomplete
        }
    }

    /// The file's SHA-256, in lowercase hex.
    nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Unpacks the archive into a fresh folder beside `folder`, then moves it into place.
    nonisolated private static func install(archive: URL, into folder: URL) throws {
        let manager = FileManager.default
        let parent = folder.deletingLastPathComponent()
        let staging = parent.appending(path: "\(folder.lastPathComponent).partial", directoryHint: .isDirectory)
        try? manager.removeItem(at: staging)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
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

    /// What the model, and anything a download left, take on the device.
    nonisolated static func usedSpace(in root: URL = root) -> Int64 {
        let manager = FileManager.default
        guard let items = manager.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in items {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    /// «نموذج الاستماع» in حسابي, «احذف»: the model goes from the device with anything a download left, and reciting
    /// aloud downloads it again when it's next used. Not while a download or an install is under way.
    func remove() async {
        switch state {
        case .downloading, .installing: return
        default: break
        }
        await RecitationTranscriber.shared.unload()
        try? FileManager.default.removeItem(at: Self.root)
        state = .absent
    }

    /// Removes other versions, installs that didn't finish, and what other versions' downloads left: everything in
    /// `root` but this version's folder, archive and resume data.
    nonisolated static func cleanUp(in root: URL = root, keeping version: String = version) {
        let manager = FileManager.default
        guard let items = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        let kept: Set<String> = [version, "\(version).aar", "\(version).resume"]
        for item in items where !kept.contains(item.lastPathComponent) {
            try? manager.removeItem(at: item)
        }
    }

    /// The background session's delegate: progress, the finished file, and what a failed download left behind.
    private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        weak var model: RecitationModel?

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : RecitationModel.downloadSize
            let fraction = min(max(Double(totalBytesWritten) / Double(expected), 0), 1)
            Task { @MainActor [model] in model?.progressed(fraction) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // The file is gone once this returns: it's moved first, then looked at.
            let manager = FileManager.default
            try? manager.createDirectory(at: RecitationModel.root, withIntermediateDirectories: true)
            try? manager.removeItem(at: RecitationModel.archive)
            let moved = (try? manager.moveItem(at: location, to: RecitationModel.archive)) != nil
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
            Task { @MainActor [model] in model?.downloaded(moved: moved, status: status) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            guard let error else { return }
            let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            Task { @MainActor [model] in model?.failed(resumeData: resumeData) }
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            Task { @MainActor in
                RecitationModel.backgroundEventsHandled?()
                RecitationModel.backgroundEventsHandled = nil
            }
        }
    }
}

/// Runs the model: 16 kHz mono audio in, the words it heard out. One stretch at a time.
actor RecitationTranscriber {
    private var kit: WhisperKit?
    private nonisolated let loaded = OSAllocatedUnfairLock(initialState: false)
    /// Stretches being heard now: the model isn't let go under them.
    private var hearing = 0

    /// Whether the model is in memory, ready to hear.
    nonisolated var isLoaded: Bool { loaded.withLock { $0 } }

    /// Loads the model, if it isn't already; this takes a moment the first time on a device, while Core ML
    /// prepares it.
    func load() async throws {
        guard kit == nil else { return }
        let config = WhisperKitConfig(modelFolder: RecitationModel.folder.path, verbose: false, logLevel: .error,
                                      prewarm: true, load: true, download: false)
        kit = try await WhisperKit(config)
        loaded.withLock { $0 = true }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let kit else { return "" }
        hearing += 1
        defer { hearing -= 1 }
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

    /// Lets the model go, once what it's hearing is heard; `load()` brings it back.
    func unload() async {
        while hearing > 0 { try? await Task.sleep(for: .milliseconds(50)) }
        guard let kit else { return }
        self.kit = nil
        loaded.withLock { $0 = false }
        await kit.unloadModels()
    }
}
