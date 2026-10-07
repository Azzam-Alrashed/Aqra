@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseStorage
import Foundation

/// An application to teach on Aqra: who the teacher is, from whom they hold their ijazah, and a copy of it. The
/// vetting team reviews it, interviews the teacher, and approves or declines it; only an administrator can make
/// a teacher (see backend/README.md).
struct TeacherApplication: Identifiable, Hashable {
    enum Status: String, CaseIterable {
        /// Waiting for review; the applicant can still change it.
        case submitted
        /// Reviewed; the team will be in touch for the interview.
        case interview
        case approved
        case rejected
    }

    /// The applicant's uid.
    let id: String
    var name: String
    var city: String
    /// One line students will read: the ijazah, the halaqah, the experience.
    var line: String
    var riwayah: String
    /// The sheikh who granted the ijazah.
    var ijazahFrom: String
    /// The chain, the date, anything else about it.
    var ijazahDetails: String
    /// How the team can reach the applicant for the interview: a phone number or an email.
    var contact: String
    /// Copies of the ijazah in the account's storage.
    var files: [String]
    var status: Status
    /// The team's note: what's next, or why it was declined.
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(id: String, name: String, city: String = "", line: String = "", riwayah: String = "حفص عن عاصم",
         ijazahFrom: String = "", ijazahDetails: String = "", contact: String = "", files: [String] = [],
         status: Status = .submitted, note: String = "", createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.city = city
        self.line = line
        self.riwayah = riwayah
        self.ijazahFrom = ijazahFrom
        self.ijazahDetails = ijazahDetails
        self.contact = contact
        self.files = files
        self.status = status
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init?(id: String, document: [String: Any]) {
        guard let name = document["name"] as? String,
              let status = (document["status"] as? String).flatMap(Status.init) else { return nil }
        self.init(id: id, name: name, city: document["city"] as? String ?? "", line: document["line"] as? String ?? "",
                  riwayah: document["riwayah"] as? String ?? "", ijazahFrom: document["ijazahFrom"] as? String ?? "",
                  ijazahDetails: document["ijazahDetails"] as? String ?? "", contact: document["contact"] as? String ?? "",
                  files: document["files"] as? [String] ?? [], status: status, note: document["note"] as? String ?? "",
                  createdAt: document["createdAt"] as? Date ?? .distantPast,
                  updatedAt: document["updatedAt"] as? Date ?? .distantPast)
    }

    /// The fields the applicant writes.
    var document: [String: Any] {
        ["name": name, "city": city, "line": line, "riwayah": riwayah, "ijazahFrom": ijazahFrom,
         "ijazahDetails": ijazahDetails, "contact": contact, "files": files, "status": status.rawValue, "note": note,
         "createdAt": createdAt, "updatedAt": updatedAt]
    }

    /// Whether the applicant has given what the team needs to review it.
    var isComplete: Bool {
        [name, city, riwayah, ijazahFrom, contact].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && !files.isEmpty
    }

    var canEdit: Bool { status == .submitted }

    /// Where an upload of the ijazah is kept.
    static func filePath(uid: String, name: String) -> String {
        "ijazahs/\(uid)/\(name)"
    }

    /// The largest upload accepted, as the storage rules say.
    static let maxFileSize = 10 * 1024 * 1024

    // MARK: - Storage

    /// Uploads a copy of the ijazah and returns its path. `contentType` is `image/…` or `application/pdf`.
    static func upload(_ data: Data, uid: String, contentType: String) async throws -> String {
        let ext = contentType == "application/pdf" ? "pdf" : contentType == "image/png" ? "png" : "jpg"
        let path = filePath(uid: uid, name: "\(UUID().uuidString).\(ext)")
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        _ = try await Storage.storage().reference(withPath: path).putDataAsync(data, metadata: metadata)
        return path
    }

    /// Lets go of every upload the account made, as far as the storage can be reached.
    static func deleteFiles(of uid: String) async {
        guard let listing = try? await Storage.storage().reference(withPath: "ijazahs/\(uid)").listAll() else { return }
        for item in listing.items {
            try? await item.delete()
        }
    }
}

extension TasmeeStore {
    /// Sends the application, or changes it while it's still waiting for review. Nothing is waited for: Firestore
    /// keeps the write while offline.
    func submit(_ application: TeacherApplication) {
        guard let uid else { return }
        var application = application
        application.status = .submitted
        application.updatedAt = .now
        let reference = database.collection("teacherApplications").document(uid)
        if self.application == nil {
            reference.setData(application.document, completion: report)
        } else {
            var changes = application.document
            changes["status"] = nil
            changes["note"] = nil
            changes["createdAt"] = nil
            reference.updateData(changes, completion: report)
        }
    }

    /// Withdraws an application that is still waiting, with its uploads.
    func withdrawApplication() async {
        guard let uid else { return }
        await TeacherApplication.deleteFiles(of: uid)
        try? await database.collection("teacherApplications").document(uid).delete()
    }
}
