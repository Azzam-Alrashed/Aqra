@preconcurrency import FirebaseFirestore
import Foundation
import Observation

/// Messages from the server and the team, in the account: outbid, a seat won, a session cancelled and refunded, a
/// teacher's tasmee' recorded, the application to teach, a payout. Shown in the app; push notifications can carry
/// them once an APNs key is set up (docs/SRS.md NTF-03).
@MainActor @Observable
final class InboxStore {
    struct Message: Identifiable, Hashable {
        enum Kind: String { case outbid, won, cancelled, refund, tasmee, application, payout }

        let id: String
        var kind: Kind
        var at: Date
        var read: Bool
        var teacherName: String
        var amount: Int
        var pages: Int
        var status: String
        var note: String
        /// The session a message is about, and when it was to start (sent with a cancellation).
        var sessionId = ""
        var startsAt: Date?
    }

    private(set) var messages: [Message] = []
    var unread: Int { messages.filter { !$0.read }.count }

    @ObservationIgnored private var uid: String?
    @ObservationIgnored private var listener: (any ListenerRegistration)?

    func attach(uid: String) {
        guard uid != self.uid else { return }
        detach()
        self.uid = uid
        listener = Firestore.firestore().collection("users").document(uid).collection("inbox")
            .order(by: "at", descending: true).limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, _ in
                MainActor.assumeIsolated {
                    self?.messages = (snapshot?.documents ?? []).compactMap { document in
                        let data = TasmeeStore.dated(document.data())
                        guard let kind = (data["kind"] as? String).flatMap(Message.Kind.init) else { return nil }
                        return Message(id: document.documentID, kind: kind, at: data["at"] as? Date ?? .distantPast,
                                       read: data["readAt"] as? Date != nil, teacherName: data["teacherName"] as? String ?? "",
                                       amount: (data["amount"] as? NSNumber)?.intValue ?? 0,
                                       pages: (data["pages"] as? NSNumber)?.intValue ?? 0,
                                       status: data["status"] as? String ?? "", note: data["note"] as? String ?? "",
                                       sessionId: data["sessionId"] as? String ?? "", startsAt: data["startsAt"] as? Date)
                    }
                }
            }
    }

    func detach() {
        listener?.remove()
        listener = nil
        uid = nil
        messages = []
    }

    func markAllRead() {
        guard let uid else { return }
        let inbox = Firestore.firestore().collection("users").document(uid).collection("inbox")
        for message in messages where !message.read {
            inbox.document(message.id).updateData(["readAt": Date.now])
        }
    }

    func delete(_ message: Message) {
        guard let uid else { return }
        Firestore.firestore().collection("users").document(uid).collection("inbox").document(message.id).delete()
    }
}
