@preconcurrency import FirebaseFirestore
import Foundation
import Observation

/// Backs the student's progress up to their account, and restores it on a new device or after a reinstall.
///
/// The device's copy stays the one the app works from. A couple of seconds after it changes, the blocks that
/// changed are written to the account (Firestore queues them while offline). The first time an account is used
/// on this install, its copy is fetched and merged with the device's (see `CloudBackup`). This is a backup across
/// devices, not live editing on two at once.
@MainActor @Observable
final class CloudSync {
    /// When the account last confirmed it holds the device's progress.
    private(set) var lastBackup: Date?

    @ObservationIgnored private let memorization: MemorizationStore
    @ObservationIgnored private let revision: RevisionStore
    @ObservationIgnored private var uid: String?
    @ObservationIgnored private var pendingUpload: Task<Void, Never>?
    /// What the account is known to hold, so only what changed is written. Nil until known: then every block is
    /// written, so a block emptied on the device (ayat unmarked) is emptied in the account too.
    @ObservationIgnored private var uploadedBlocks: [Int: CloudBackup.Block]?
    @ObservationIgnored private var uploadedRevision: RevisionStore.Snapshot?
    /// Changes aren't backed up while a restore is replacing the device's copy.
    @ObservationIgnored private var isRestoring = false

    /// The account whose copy this install has already merged, so it's merged once rather than on every launch.
    private static let restoredKey = "cloud.restoredAccount"

    init(memorization: MemorizationStore, revision: RevisionStore) {
        self.memorization = memorization
        self.revision = revision
        memorization.onChange = { [weak self] in self?.scheduleUpload() }
        revision.onChange = { [weak self] in self?.scheduleUpload() }
    }

    private var database: Firestore { Firestore.firestore() }

    private func user(_ uid: String) -> DocumentReference {
        database.collection("users").document(uid)
    }

    // MARK: - The account in use

    /// Starts backing up to an account, merging its copy first if this install hasn't yet.
    func attach(uid: String) async {
        guard uid != self.uid else { return }
        self.uid = uid
        uploadedBlocks = nil
        uploadedRevision = nil
        lastBackup = nil
        if UserDefaults.standard.string(forKey: Self.restoredKey) != uid {
            await restoreAndMerge(uid: uid)
        }
        scheduleUpload(after: .zero)
    }

    /// Stops backing up, before signing out or deleting the account.
    func detach() {
        pendingUpload?.cancel()
        pendingUpload = nil
        uid = nil
        lastBackup = nil
        UserDefaults.standard.removeObject(forKey: Self.restoredKey)
    }

    /// Clears the device's progress, after signing out: the account keeps its copy.
    func clearDevice() {
        isRestoring = true
        memorization.replaceAll([:])
        revision.apply(.empty)
        isRestoring = false
    }

    // MARK: - Restoring

    private func restoreAndMerge(uid: String) async {
        do {
            let blocks = try await user(uid).collection("memory").getDocuments()
            let state = try await user(uid).collection("revision").document("state").getDocument()
            guard uid == self.uid else { return }

            var remoteBlocks: [Int: CloudBackup.Block] = [:]
            for document in blocks.documents {
                guard let index = Int(document.documentID.dropFirst("block-".count)) else { continue }
                remoteBlocks[index] = Self.block(from: document.data()["ayahs"])
            }
            let remoteRevision = (state.data()?["json"] as? String).flatMap(CloudBackup.decodeRevision)

            isRestoring = true
            memorization.replaceAll(CloudBackup.merge(memorization.ayahs, CloudBackup.ayahs(in: remoteBlocks.values)))
            if let remoteRevision {
                revision.apply(CloudBackup.merge(revision.snapshot, remoteRevision))
            }
            isRestoring = false
            uploadedBlocks = remoteBlocks
            uploadedRevision = remoteRevision
            UserDefaults.standard.set(uid, forKey: Self.restoredKey)
        } catch {
            // Offline or refused: the next launch tries again, and nothing on the device is lost meanwhile.
            isRestoring = false
        }
    }

    /// A block as Firestore returns it: numbers arrive as `NSNumber`s.
    private static func block(from value: Any?) -> CloudBackup.Block {
        guard let rows = value as? [String: [Any]] else { return [:] }
        return rows.compactMapValues { row in
            let numbers = row.compactMap { ($0 as? NSNumber)?.doubleValue }
            return numbers.count == row.count ? numbers : nil
        }
    }

    // MARK: - Backing up

    private func scheduleUpload(after delay: Duration = .seconds(2)) {
        guard uid != nil, !isRestoring else { return }
        pendingUpload?.cancel()
        pendingUpload = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            try? await self?.upload()
        }
    }

    /// Writes whatever changed since the account last heard from this device, and waits for the account to
    /// confirm it. Throws when it can't be reached.
    func upload() async throws {
        guard let uid else { return }
        let blocks = CloudBackup.blocks(memorization.ayahs)
        let changed = uploadedBlocks.map { uploaded in blocks.filter { uploaded[$0.key, default: [:]] != $0.value } } ?? blocks
        let snapshot = revision.snapshot
        let revisionChanged = snapshot != uploadedRevision && (uploadedRevision != nil || snapshot != .empty)
        guard !changed.isEmpty || revisionChanged else {
            lastBackup = lastBackup ?? .now
            return
        }

        let batch = database.batch()
        let user = user(uid)
        batch.setData(["updatedAt": FieldValue.serverTimestamp()], forDocument: user, merge: true)
        for (index, block) in changed {
            batch.setData(["ayahs": block, "updatedAt": FieldValue.serverTimestamp()],
                          forDocument: user.collection("memory").document(CloudBackup.blockID(index)))
        }
        if revisionChanged {
            batch.setData(["json": try CloudBackup.encode(snapshot), "updatedAt": FieldValue.serverTimestamp()],
                          forDocument: user.collection("revision").document("state"))
        }
        try await batch.commit()
        guard uid == self.uid else { return }
        uploadedBlocks = (uploadedBlocks ?? [:]).merging(changed) { _, new in new }
        if revisionChanged { uploadedRevision = snapshot }
        lastBackup = .now
    }

    /// Uploads, giving up after a while: signing out and deleting need the account to answer, not a queue.
    func uploadNow(timeout: Duration = .seconds(12)) async throws {
        pendingUpload?.cancel()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.upload() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CloudSyncError.timedOut
            }
            try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Deleting

    /// Deletes everything the account holds of the student's progress.
    func deleteAccountData(uid: String) async throws {
        let user = user(uid)
        let batch = database.batch()
        for index in 0..<CloudBackup.blockCount {
            batch.deleteDocument(user.collection("memory").document(CloudBackup.blockID(index)))
        }
        batch.deleteDocument(user.collection("revision").document("state"))
        batch.deleteDocument(user)
        try await batch.commit()
    }
}

enum CloudSyncError: Error {
    case timedOut
}
