import Foundation
import MetricKit
import os

/// Crash, hang and other diagnostics from MetricKit, kept on the phone and sent nowhere (docs/SRS.md ATT-10): iOS
/// hands them over at most once a day, and each is saved as Apple's own JSON in Application Support/Diagnostics, the
/// newest few kept, with a line in the log. A developer with the phone reads them there (Xcode, Devices, the app's
/// container) or in Console. Crash reports from the App Store and TestFlight reach App Store Connect on their own,
/// from those who share them with developers; no crash service is added, so no data leaves the europe-west1 rule.
final class Diagnostics: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = Diagnostics()
    /// How many payloads are kept: enough for a week of daily deliveries and then some.
    static let kept = 20

    private static let log = Logger(subsystem: "com.azzamalrashed.aqra", category: "diagnostics")

    static var folder: URL { URL.applicationSupportDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory) }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let summary = Self.summary(crashes: payload.crashDiagnostics?.count ?? 0, hangs: payload.hangDiagnostics?.count ?? 0,
                                       cpu: payload.cpuExceptionDiagnostics?.count ?? 0, disk: payload.diskWriteExceptionDiagnostics?.count ?? 0)
            Self.log.error("MetricKit diagnostics until \(payload.timeStampEnd, privacy: .public): \(summary, privacy: .public)")
            do {
                try Self.save(payload.jsonRepresentation(), endingAt: payload.timeStampEnd)
            } catch {
                Self.log.error("Couldn't keep the diagnostics: \(error, privacy: .public)")
            }
        }
    }

    /// «1 crash, 2 hangs»: what a payload holds, for the log.
    static func summary(crashes: Int, hangs: Int, cpu: Int, disk: Int) -> String {
        let parts = [(crashes, "crash", "crashes"), (hangs, "hang", "hangs"), (cpu, "CPU exception", "CPU exceptions"),
                     (disk, "disk-write exception", "disk-write exceptions")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }
        return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
    }

    /// Saves a payload, named by when it ends, and keeps only the newest `kept` in the folder.
    static func save(_ json: Data, endingAt date: Date, in folder: URL = folder, kept: Int = kept) throws {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = date.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false)
            .timeSeparator(.omitted))
        try json.write(to: folder.appending(path: "\(name).json"), options: .atomic)
        let saved = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in saved.dropFirst(kept) {
            try? files.removeItem(at: old)
        }
    }
}
