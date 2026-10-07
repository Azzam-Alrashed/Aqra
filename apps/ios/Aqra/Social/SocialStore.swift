@preconcurrency import FirebaseFirestore
import Foundation
import Observation

/// Friends and competitions, through the account: the friends this account has, the competitions it's in, and
/// the student's own score in each race among friends, reported from what they did on this device. A teacher's
/// competitions are scored by the server from the teacher's own records. See backend/README.md.
@MainActor @Observable
final class SocialStore {
    private(set) var friendships: [Friendship] = []
    private(set) var competitions: [Competition] = []
    var problem: AccountStore.Problem?

    @ObservationIgnored private let memorization: MemorizationStore
    @ObservationIgnored private let revision: RevisionStore
    @ObservationIgnored private(set) var uid: String?
    @ObservationIgnored private var listeners: [any ListenerRegistration] = []
    /// The scores last reported, by competition, so an unchanged score isn't written again.
    @ObservationIgnored private var reported: [String: Int] = [:]

    init(memorization: MemorizationStore, revision: RevisionStore) {
        self.memorization = memorization
        self.revision = revision
    }

    private var database: Firestore { Firestore.firestore() }

    var friends: [(uid: String, name: String)] {
        guard let uid else { return [] }
        return friendships.map { $0.friend(of: uid) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - The account in use

    func attach(uid: String) {
        guard uid != self.uid else { return }
        detach()
        self.uid = uid
        listeners.append(database.collection("friendships").whereField("members", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                MainActor.assumeIsolated {
                    guard let self, let snapshot else { return }
                    self.friendships = snapshot.documents.compactMap { Friendship(id: $0.documentID, document: TasmeeStore.dated($0.data())) }
                }
            })
        listeners.append(database.collection("competitions").whereField("memberUids", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                MainActor.assumeIsolated {
                    guard let self, let snapshot else { return }
                    self.competitions = snapshot.documents
                        .compactMap { Competition(id: $0.documentID, document: TasmeeStore.dated($0.data())) }
                        .sorted { ($0.endsAt > .now ? 0 : 1, $0.endsAt) < ($1.endsAt > .now ? 0 : 1, $1.endsAt) }
                }
            })
    }

    func detach() {
        for listener in listeners { listener.remove() }
        listeners = []
        uid = nil
        friendships = []
        competitions = []
        reported = [:]
        problem = nil
    }

    // MARK: - Friends

    /// Creates an invitation for this account, valid for a week.
    func createInvite(name: String) async throws -> FriendInvite {
        guard let uid else { throw TasmeeError.notSignedIn }
        for _ in 0..<5 {
            let invite = FriendInvite(id: PeerRequest.randomCode(), ownerUid: uid, ownerName: name)
            do {
                try await database.collection("friendInvites").document(invite.id).setData(invite.document)
                return invite
            } catch let error as NSError where error.domain == FirestoreErrorDomain
                && error.code == FirestoreErrorCode.permissionDenied.rawValue {
                continue
            }
        }
        throw TasmeeError.codeUnavailable
    }

    func invite(code: String) async throws -> FriendInvite? {
        let snapshot = try await database.collection("friendInvites").document(code).getDocument()
        guard let data = snapshot.data(), let invite = FriendInvite(id: code, document: TasmeeStore.dated(data)), invite.isValid() else {
            return nil
        }
        return invite
    }

    /// Accepts an invitation: the two become friends.
    func accept(_ invite: FriendInvite, name: String) async throws {
        guard let uid, invite.ownerUid != uid else { return }
        let friendship = Friendship(id: Friendship.id(uid, invite.ownerUid), members: [invite.ownerUid, uid],
                                    names: [invite.ownerUid: invite.ownerName, uid: name])
        try await database.collection("friendships").document(friendship.id).setData(friendship.document(inviteCode: invite.id))
    }

    func remove(friendUid: String) {
        guard let uid else { return }
        database.collection("friendships").document(Friendship.id(uid, friendUid)).delete(completion: report)
    }

    // MARK: - Competitions

    /// Starts a competition with some friends (or, for a teacher, some of their students); a khatmah is made with
    /// its thirty parts, free to claim.
    func start(kind: Competition.Kind, title: String, metric: Competition.Metric, days: Int, ownerName: String,
               members: [String]) async throws {
        guard let uid else { throw TasmeeError.notSignedIn }
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86_400)
        let reference = database.collection("competitions").document()
        let competition = Competition(id: reference.documentID, kind: kind, title: title, metric: metric, ownerUid: uid,
                                      ownerName: ownerName, startsAt: start, endsAt: end,
                                      memberUids: [uid] + members.filter { $0 != uid })
        let batch = database.batch()
        batch.setData(competition.document, forDocument: reference)
        if kind == .khatmah {
            for juz in 1...30 {
                batch.setData(KhatmahPart(id: juz).document, forDocument: reference.collection("parts").document(String(juz)))
            }
        }
        try await batch.commit()
    }

    /// Leaves a competition: this member's standing goes with them.
    func leave(_ competition: Competition) {
        guard let uid else { return }
        let reference = database.collection("competitions").document(competition.id)
        reference.collection("members").document(uid).delete()
        reference.updateData(["memberUids": FieldValue.arrayRemove([uid])], completion: report)
    }

    /// Ends a competition now (its owner only).
    func end(_ competition: Competition) {
        database.collection("competitions").document(competition.id).updateData(["endsAt": Date.now], completion: report)
    }

    func members(of competition: Competition) -> AsyncStream<[CompetitionMember]> {
        AsyncStream { continuation in
            let registration = database.collection("competitions").document(competition.id).collection("members")
                .addSnapshotListener { snapshot, _ in
                    guard let snapshot else { return }
                    continuation.yield(snapshot.documents.compactMap { CompetitionMember(id: $0.documentID, document: $0.data()) })
                }
            let box = RegistrationBox(registration)
            continuation.onTermination = { _ in box.remove() }
        }
    }

    func parts(of competition: Competition) -> AsyncStream<[KhatmahPart]> {
        AsyncStream { continuation in
            let registration = database.collection("competitions").document(competition.id).collection("parts")
                .addSnapshotListener { snapshot, _ in
                    guard let snapshot else { return }
                    continuation.yield(snapshot.documents.compactMap { KhatmahPart(id: $0.documentID, document: $0.data()) }
                        .sorted { $0.id < $1.id })
                }
            let box = RegistrationBox(registration)
            continuation.onTermination = { _ in box.remove() }
        }
    }

    /// Claims a free part, gives one back, or marks one finished.
    func claim(_ part: KhatmahPart, in competition: Competition, name: String) {
        guard let uid else { return }
        partReference(part, competition).updateData(["claimedBy": uid, "claimedName": name, "done": false], completion: report)
    }

    func release(_ part: KhatmahPart, in competition: Competition) {
        partReference(part, competition).updateData(["claimedBy": NSNull(), "claimedName": "", "done": false], completion: report)
    }

    func setDone(_ done: Bool, _ part: KhatmahPart, in competition: Competition) {
        partReference(part, competition).updateData(["done": done], completion: report)
    }

    private func partReference(_ part: KhatmahPart, _ competition: Competition) -> DocumentReference {
        database.collection("competitions").document(competition.id).collection("parts").document(String(part.id))
    }

    /// Reports this student's score in each race among friends that's running, from what they did on this device.
    func reportScores(name: String) {
        guard let uid else { return }
        for competition in competitions where competition.kind == .friends && competition.isRunning() {
            let score = CompetitionScore.score(competition.metric, from: competition.startsAt, to: competition.endsAt,
                                               memorization: memorization, revision: revision)
            guard reported[competition.id] != score else { continue }
            reported[competition.id] = score
            database.collection("competitions").document(competition.id).collection("members").document(uid)
                .setData(["name": name, "score": score, "updatedAt": Date.now], completion: report)
        }
    }

    nonisolated func report(_ error: Error?) {
        guard let error else { return }
        MainActor.assumeIsolated { problem = AccountStore.problem(for: error) }
    }

    // MARK: - Deleting

    /// Deletes what the account holds of friends and competitions: its friendships and invitations, its places in
    /// others' competitions, and the competitions it started.
    func deleteAccountData(uid: String) async throws {
        var references = try await database.collection("friendships").whereField("members", arrayContains: uid).getDocuments()
            .documents.map(\.reference)
        references += try await database.collection("friendInvites").whereField("ownerUid", isEqualTo: uid).getDocuments()
            .documents.map(\.reference)
        let competitions = try await database.collection("competitions").whereField("memberUids", arrayContains: uid).getDocuments()
        for competition in competitions.documents {
            if competition.data()["ownerUid"] as? String == uid {
                references += try await competition.reference.collection("members").getDocuments().documents.map(\.reference)
                references += try await competition.reference.collection("parts").getDocuments().documents.map(\.reference)
                references.append(competition.reference)
            } else {
                references.append(competition.reference.collection("members").document(uid))
                try await competition.reference.updateData(["memberUids": FieldValue.arrayRemove([uid])])
            }
        }
        try await TasmeeStore.delete(references, in: database)
    }
}

/// Carries a listener into a stream's termination handler.
private final class RegistrationBox: @unchecked Sendable {
    private let registration: any ListenerRegistration

    init(_ registration: any ListenerRegistration) {
        self.registration = registration
    }

    func remove() {
        registration.remove()
    }
}
