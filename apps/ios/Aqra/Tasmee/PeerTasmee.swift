@preconcurrency import FirebaseFirestore
import Foundation

/// A student's invitation to a friend to hear their tasmee': a short code, shown as text and as a QR code, valid
/// for half an hour. The friend's app writes what they heard into the student's account, as a peer's tasmee'.
struct PeerRequest: Identifiable, Hashable {
    /// The code: six characters that can't be mistaken for one another.
    let id: String
    var studentUid: String
    /// The student's name as shown to the friend, or nil for an anonymous student.
    var studentName: String?
    /// Where the friend's Mushaf opens: the student's next page to revise.
    var startPage: Int?
    var createdAt: Date
    var expiresAt: Date

    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let codeLength = 6
    /// How long a code stays valid. The rules accept at most 31 minutes.
    static let lifetime: TimeInterval = 30 * 60

    init(id: String, studentUid: String, studentName: String?, startPage: Int? = nil, createdAt: Date = .now,
         expiresAt: Date = .now.addingTimeInterval(PeerRequest.lifetime)) {
        self.id = id
        self.studentUid = studentUid
        self.studentName = studentName
        self.startPage = startPage
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    init?(id: String, document: [String: Any]) {
        guard let studentUid = document["studentUid"] as? String, let createdAt = document["createdAt"] as? Date,
              let expiresAt = document["expiresAt"] as? Date else { return nil }
        self.init(id: id, studentUid: studentUid, studentName: document["studentName"] as? String,
                  startPage: (document["startPage"] as? NSNumber)?.intValue, createdAt: createdAt, expiresAt: expiresAt)
    }

    var document: [String: Any] {
        var document: [String: Any] = ["studentUid": studentUid, "createdAt": createdAt, "expiresAt": expiresAt]
        if let studentName { document["studentName"] = studentName }
        if let startPage { document["startPage"] = startPage }
        return document
    }

    func isValid(at date: Date = .now) -> Bool { expiresAt > date }

    /// The link a QR code carries: the system camera opens it in Aqra.
    var link: URL { URL(string: "aqra://peer/\(id)")! }

    static func randomCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<codeLength).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
    }

    /// A code as typed: upper-cased, without spaces or dashes.
    static func normalize(_ typed: String) -> String {
        typed.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    static func isWellFormed(_ code: String) -> Bool {
        code.count == codeLength && code.allSatisfy(alphabet.contains)
    }

    /// The code in a link (`aqra://peer/CODE`), if it's one.
    static func code(in url: URL) -> String? {
        guard url.scheme == "aqra", url.host == "peer" else { return nil }
        let code = normalize(url.lastPathComponent)
        return isWellFormed(code) ? code : nil
    }
}

extension TasmeeStore {
    /// Creates a peer request for this student. Codes are random; if one is taken, another is tried.
    func createPeerRequest(studentName: String?, startPage: Int?) async throws -> PeerRequest {
        guard let uid else { throw TasmeeError.notSignedIn }
        for _ in 0..<5 {
            let request = PeerRequest(id: PeerRequest.randomCode(), studentUid: uid, studentName: studentName,
                                      startPage: startPage)
            do {
                try await database.collection("peerRequests").document(request.id).setData(request.document)
                return request
            } catch let error as NSError where error.domain == FirestoreErrorDomain
                && error.code == FirestoreErrorCode.permissionDenied.rawValue {
                // The code exists already (the rules refuse to overwrite it); try another.
                continue
            }
        }
        throw TasmeeError.codeUnavailable
    }

    /// The request behind a code, if it exists and is still valid.
    func peerRequest(code: String) async throws -> PeerRequest? {
        let snapshot = try await database.collection("peerRequests").document(code).getDocument()
        guard let data = snapshot.data(), let request = PeerRequest(id: code, document: Self.dated(data)),
              request.isValid() else { return nil }
        return request
    }

    /// Writes what this user heard from a friend into the friend's account; the friend's app applies it as a peer's
    /// tasmee'. Queued while offline.
    func recordPeerTasmee(for request: PeerRequest, listenerName: String?, pages: [Int], stumbles: [Int],
                          mistakes: [Mistake], at date: Date = .now) {
        guard let uid else { return }
        let reference = user(request.studentUid).collection("tasmee").document()
        let record = TasmeeRecord(id: reference.documentID, kind: .peer, teacherId: uid, teacherName: listenerName ?? "",
                                  sessionId: request.id, at: date, pages: pages.sorted(), stumbles: stumbles.sorted(),
                                  mistakes: mistakes.filter { $0.type != .memorization })
        reference.setData(record.document, completion: report)
    }
}
