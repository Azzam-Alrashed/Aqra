@preconcurrency import FirebaseFirestore
import Foundation
import Observation
import os

/// Backs the student's progress up to their account, and keeps it whole across devices.
///
/// The device's copy stays the one the app works from. Whenever an account is attached and whenever the app comes
/// back to the foreground after another device wrote to the account, the account's copy is fetched and merged
/// into the device's (see `CloudBackup`: unions, never a blind overwrite), and a couple of seconds after any
/// change, only what changed is written back, row by row. Nothing is ever written before the account's copy has
/// been merged in this session: a device that can't reach the account keeps its changes until it can.
@MainActor @Observable
final class CloudSync {
    /// When the account last confirmed it holds the device's progress.
    private(set) var lastBackup: Date?
    /// When the account's copy was last merged into the device's, so the screens can rebuild from it.
    private(set) var lastMerge: Date?

    @ObservationIgnored private let memorization: MemorizationStore
    @ObservationIgnored private let revision: RevisionStore
    @ObservationIgnored private let journey: Journey?
    @ObservationIgnored private let store: any CloudStore
    /// Tells this install's writes from another device's, so coming back to the foreground fetches the account's
    /// copy only when another device wrote it since.
    @ObservationIgnored let installID: String
    @ObservationIgnored private var uid: String?
    @ObservationIgnored private var pendingUpload: Task<Void, Never>?
    /// The rows the account is known to hold, from the last merge and this install's writes since, so only what
    /// changed is written. Nil until the account's copy has been merged in this session: nothing is written before.
    @ObservationIgnored private var uploadedBlocks: [Int: CloudBackup.Block]?
    @ObservationIgnored private var uploadedRevision: RevisionStore.Snapshot?
    @ObservationIgnored private var uploadedJourney: Journey.Snapshot?
    /// Whether the account's revision record and journey could be read. One written by a newer app that this one
    /// can't make sense of is left as it is rather than overwritten.
    @ObservationIgnored private var remoteRevisionReadable = true
    @ObservationIgnored private var remoteJourneyReadable = true
    /// Changes aren't backed up while a merge is replacing the device's copy.
    @ObservationIgnored private var isRestoring = false
    @ObservationIgnored private var isMerging = false
    /// Set while the account is being deleted: nothing is written back to it.
    @ObservationIgnored private var uploadsStopped = false

    /// The key an earlier version kept its "already merged" marker under; it's no longer read, since the account's
    /// copy is merged in every session (a marker could come back with a device backup and skip the merge).
    private static let oldRestoredKey = "cloud.restoredAccount"
    private static let log = Logger(subsystem: "com.azzamalrashed.aqra", category: "sync")
    /// A fetch right as the app comes back can fail while the connection is re-established; it's tried again.
    private static let mergeAttempts = 3

    init(memorization: MemorizationStore, revision: RevisionStore, journey: Journey? = nil,
         store: any CloudStore = FirestoreCloudStore(), installID: String = InstallID.current) {
        self.memorization = memorization
        self.revision = revision
        self.journey = journey
        self.store = store
        self.installID = installID
        memorization.onChange = { [weak self] in self?.scheduleUpload() }
        revision.onChange = { [weak self] in self?.scheduleUpload() }
        journey?.onChange = { [weak self] in self?.scheduleUpload() }
        UserDefaults.standard.removeObject(forKey: Self.oldRestoredKey)
    }

    // MARK: - The account in use

    /// Starts backing up to an account: its copy is merged into the device's first, then what the device adds is
    /// written back.
    func attach(uid: String) async {
        guard uid != self.uid else { return }
        self.uid = uid
        uploadsStopped = false
        forgetAccount()
        await mergeWithAccount(uid: uid, attempts: Self.mergeAttempts)
        scheduleUpload(after: .zero)
    }

    /// Back in the foreground: if another device wrote to the account meanwhile, its copy is merged in. One read
    /// tells; the copy itself is fetched only when it's needed.
    func syncIfChanged() async {
        guard let uid, !isMerging, !uploadsStopped else { return }
        if uploadedBlocks != nil {
            var writer: String??
            for attempt in 1...Self.mergeAttempts {
                writer = try? await store.lastWriter(uid: uid)
                if writer != nil || attempt == Self.mergeAttempts { break }
                try? await Task.sleep(for: .seconds(2))
            }
            guard uid == self.uid, let writer, writer != installID else { return }
        }
        await mergeWithAccount(uid: uid, attempts: Self.mergeAttempts)
        scheduleUpload(after: .zero)
    }

    /// Stops backing up, before signing out or deleting the account.
    func detach() {
        pendingUpload?.cancel()
        pendingUpload = nil
        uid = nil
        forgetAccount()
    }

    /// Stops writing to the account, before its data is deleted: a backup half-way through would bring it back.
    func stopUploads() {
        uploadsStopped = true
        pendingUpload?.cancel()
        pendingUpload = nil
    }

    /// Writes again, after a deletion that didn't go through.
    func resumeUploads() {
        uploadsStopped = false
        scheduleUpload(after: .zero)
    }

    /// Clears the device's progress, after signing out: the account keeps its copy.
    func clearDevice() {
        isRestoring = true
        memorization.replaceAll([:])
        revision.apply(.empty)
        journey?.apply(.empty)
        isRestoring = false
    }

    private func forgetAccount() {
        uploadedBlocks = nil
        uploadedRevision = nil
        uploadedJourney = nil
        remoteRevisionReadable = true
        remoteJourneyReadable = true
        lastBackup = nil
    }

    // MARK: - Merging the account's copy

    private func mergeWithAccount(uid: String, attempts: Int = 1) async {
        isMerging = true
        defer { isMerging = false }
        do {
            var remote: CloudProgress?
            for attempt in 1...max(attempts, 1) {
                do {
                    remote = try await store.fetchProgress(uid: uid)
                    break
                } catch where attempt < attempts {
                    Self.log.notice("fetching the account's copy failed (attempt \(attempt)): \(String(describing: error), privacy: .public)")
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            guard let remote, uid == self.uid else { return }

            let remoteMemory = CloudBackup.memory(in: remote.blocks.values)
            var remoteRevision = remote.revisionJSON.flatMap(CloudBackup.decodeRevision)
            remoteRevisionReadable = remote.revisionJSON == nil || remoteRevision != nil
            // The days are kept beside the record too, only ever added to; whatever the record says, they count.
            if remoteRevision != nil || !remote.revisedDays.isEmpty || !remote.completedDays.isEmpty {
                var record = remoteRevision ?? .empty
                record.revisedDays = Set(record.revisedDays).union(remote.revisedDays.map(Date.init(timeIntervalSinceReferenceDate:))).sorted()
                let completed = Set(record.completedDays ?? []).union(remote.completedDays.map(Date.init(timeIntervalSinceReferenceDate:)))
                record.completedDays = completed.isEmpty ? nil : completed.sorted()
                remoteRevision = record
            }
            let remoteJourney = remote.journeyJSON.flatMap(CloudBackup.decodeJourney)
            remoteJourneyReadable = remote.journeyJSON == nil || remoteJourney != nil

            isRestoring = true
            memorization.replaceAll(CloudBackup.merge(memorization.memory, remoteMemory))
            if let remoteRevision {
                revision.apply(CloudBackup.merge(revision.snapshot, remoteRevision))
            }
            if let journey, let remoteJourney {
                journey.apply(Journey.Snapshot.merge(journey.snapshot, remoteJourney))
            }
            isRestoring = false
            uploadedBlocks = remote.blocks
            uploadedRevision = remoteRevision
            uploadedJourney = remoteJourney
            lastMerge = .now
            Self.log.info("merged the account's copy: \(remote.blocks.count) blocks")
        } catch {
            // Offline or refused: nothing on the device is lost, and nothing is written until it goes through.
            isRestoring = false
            Self.log.notice("merging the account's copy failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Backing up

    private func scheduleUpload(after delay: Duration = .seconds(2)) {
        guard uid != nil, !isRestoring, !uploadsStopped else { return }
        pendingUpload?.cancel()
        pendingUpload = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            try? await self?.upload()
        }
    }

    /// Writes whatever changed since the account was last read, and waits for the account to confirm it. Throws
    /// when it can't be reached.
    func upload() async throws {
        guard let uid, !uploadsStopped else { return }
        // The account's copy is merged first (the attach may have happened offline), or nothing is written.
        if uploadedBlocks == nil {
            await mergeWithAccount(uid: uid)
            guard uid == self.uid else { return }
            guard uploadedBlocks != nil else { throw CloudSyncError.notRestored }
        }
        let known = uploadedBlocks ?? [:]
        var rows: [Int: CloudBackup.Block] = [:]
        for (index, block) in CloudBackup.blocks(memorization.memory) {
            let changed = block.filter { known[index]?[$0.key] != $0.value }
            if !changed.isEmpty { rows[index] = changed }
        }
        let snapshot = revision.snapshot
        let revisionChanged = remoteRevisionReadable && snapshot != uploadedRevision && (uploadedRevision != nil || snapshot != .empty)
        let journeySnapshot = journey?.snapshot
        let journeyChanged = remoteJourneyReadable && journeySnapshot != nil && journeySnapshot != uploadedJourney
            && (uploadedJourney != nil || journeySnapshot != .empty)
        guard !rows.isEmpty || revisionChanged || journeyChanged else {
            lastBackup = lastBackup ?? .now
            return
        }

        var write = CloudWrite(writer: installID)
        write.rows = rows
        if revisionChanged {
            write.revisionJSON = try CloudBackup.encode(snapshot)
            write.revisedDays = snapshot.revisedDays.map(\.timeIntervalSinceReferenceDate)
            write.completedDays = (snapshot.completedDays ?? []).map(\.timeIntervalSinceReferenceDate)
        }
        if journeyChanged, let journeySnapshot {
            write.journeyJSON = try CloudBackup.encode(journeySnapshot)
        }
        try await store.write(uid: uid, write)
        guard uid == self.uid, !uploadsStopped else { return }
        var blocks = uploadedBlocks ?? [:]
        for (index, changed) in rows {
            blocks[index, default: [:]].merge(changed) { _, new in new }
        }
        uploadedBlocks = blocks
        if revisionChanged { uploadedRevision = snapshot }
        if journeyChanged { uploadedJourney = journeySnapshot }
        lastBackup = .now
    }

    /// Uploads, giving up after a while: signing out and deleting need the account to answer, not a queue.
    func uploadNow(timeout: Duration = .seconds(12)) async throws {
        pendingUpload?.cancel()
        try await withServerTimeout(timeout) { try await self.upload() }
    }

    // MARK: - Deleting

    /// Deletes everything the account holds of the student's progress.
    func deleteAccountData(uid: String) async throws {
        try await store.deleteProgress(uid: uid)
    }
}

enum CloudSyncError: Error {
    case timedOut
    /// The account's copy couldn't be fetched to merge with this device's, so nothing was written.
    case notRestored
}

// MARK: - The account's documents

/// The account's progress as the store holds it: the blocks of rows, the revision record with its days, and the
/// journey, each as it was written (see `CloudBackup` for the layout).
struct CloudProgress: Equatable {
    var blocks: [Int: CloudBackup.Block] = [:]
    var revisionJSON: String?
    /// Seconds since 2001, as the JSON keeps dates.
    var revisedDays: [Double] = []
    var completedDays: [Double] = []
    var journeyJSON: String?
}

/// What a device writes: the rows that changed, merged into their blocks, and the records that changed.
struct CloudWrite: Equatable {
    var rows: [Int: CloudBackup.Block] = [:]
    var revisionJSON: String?
    /// Added to the days the account already holds, never replacing them.
    var revisedDays: [Double] = []
    var completedDays: [Double] = []
    var journeyJSON: String?
    var writer: String
}

/// What a device needs of the account: the documents under `users/{uid}`, read and written as plain values, so
/// the backup can be tested with a fake store in place of Firestore.
@MainActor
protocol CloudStore: AnyObject {
    /// The install that last wrote the account's progress, or nil when nothing says.
    func lastWriter(uid: String) async throws -> String?
    /// The account's progress, from the server: offline, the cache would answer with whatever this install holds.
    func fetchProgress(uid: String) async throws -> CloudProgress
    func write(uid: String, _ write: CloudWrite) async throws
    func deleteProgress(uid: String) async throws
}

/// The account's documents in Firestore.
@MainActor
final class FirestoreCloudStore: CloudStore {
    private var database: Firestore { Firestore.firestore() }

    private func user(_ uid: String) -> DocumentReference {
        database.collection("users").document(uid)
    }

    func lastWriter(uid: String) async throws -> String? {
        try await user(uid).getDocument(source: .server).data()?["lastWriter"] as? String
    }

    func fetchProgress(uid: String) async throws -> CloudProgress {
        let blocks = try await user(uid).collection("memory").getDocuments(source: .server)
        let state = try await user(uid).collection("revision").document("state").getDocument(source: .server)
        let journey = try await user(uid).collection("journey").document("state").getDocument(source: .server)
        var progress = CloudProgress()
        for document in blocks.documents {
            guard let index = Int(document.documentID.dropFirst("block-".count)) else { continue }
            progress.blocks[index] = Self.block(from: document.data()["ayahs"])
        }
        progress.revisionJSON = state.data()?["json"] as? String
        progress.revisedDays = Self.numbers(from: state.data()?["revisedDays"])
        progress.completedDays = Self.numbers(from: state.data()?["completedDays"])
        progress.journeyJSON = journey.data()?["json"] as? String
        return progress
    }

    func write(uid: String, _ write: CloudWrite) async throws {
        let batch = database.batch()
        let user = user(uid)
        batch.setData(["updatedAt": FieldValue.serverTimestamp(), "lastWriter": write.writer], forDocument: user, merge: true)
        for (index, rows) in write.rows {
            batch.setData(["ayahs": rows, "updatedAt": FieldValue.serverTimestamp()],
                          forDocument: user.collection("memory").document(CloudBackup.blockID(index)), merge: true)
        }
        if let json = write.revisionJSON {
            var data: [String: Any] = ["json": json, "updatedAt": FieldValue.serverTimestamp()]
            if !write.revisedDays.isEmpty { data["revisedDays"] = FieldValue.arrayUnion(write.revisedDays) }
            if !write.completedDays.isEmpty { data["completedDays"] = FieldValue.arrayUnion(write.completedDays) }
            batch.setData(data, forDocument: user.collection("revision").document("state"), merge: true)
        }
        if let json = write.journeyJSON {
            batch.setData(["json": json, "updatedAt": FieldValue.serverTimestamp()],
                          forDocument: user.collection("journey").document("state"), merge: true)
        }
        try await batch.commit()
    }

    func deleteProgress(uid: String) async throws {
        let user = user(uid)
        let batch = database.batch()
        for index in 0..<CloudBackup.blockCount {
            batch.deleteDocument(user.collection("memory").document(CloudBackup.blockID(index)))
        }
        batch.deleteDocument(user.collection("revision").document("state"))
        batch.deleteDocument(user.collection("journey").document("state"))
        batch.deleteDocument(user)
        try await batch.commit()
    }

    /// A block as Firestore returns it: numbers arrive as `NSNumber`s.
    private static func block(from value: Any?) -> CloudBackup.Block {
        guard let rows = value as? [String: [Any]] else { return [:] }
        return rows.compactMapValues { row in
            let numbers = row.compactMap { ($0 as? NSNumber)?.doubleValue }
            return numbers.count == row.count ? numbers : nil
        }
    }

    private static func numbers(from value: Any?) -> [Double] {
        (value as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue }.filter(\.isFinite) ?? []
    }
}

/// A name for this install, made once and kept in a file left out of device backups (a backup restored on another
/// phone makes a new one), so the account can tell which device wrote last.
enum InstallID {
    static let current: String = {
        guard var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("install-id") else { return UUID().uuidString }
        if let id = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        let id = UUID().uuidString
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(id.utf8).write(to: url, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return id
    }()
}

/// Waits for something that needs the server's answer, but no longer than `timeout`. Firestore keeps a write until
/// it reaches the server and only answers then, so offline it would wait forever. A task group can't give up on it:
/// a group waits for every child, and Firestore's calls don't stop when cancelled.
@MainActor
func withServerTimeout<T: Sendable>(_ timeout: Duration = .seconds(12),
                                    _ work: @escaping @MainActor () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let answer = FirstAnswer(continuation)
        answer.timer = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { answer.resume(with: .failure(CloudSyncError.timedOut)) }
        }
        Task {
            do {
                answer.resume(with: .success(try await work()))
            } catch {
                answer.resume(with: .failure(error))
            }
        }
    }
}

/// Resumes a continuation once, with whichever answer comes first.
@MainActor
private final class FirstAnswer<T: Sendable> {
    private var continuation: CheckedContinuation<T, Error>?
    var timer: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        timer?.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}
