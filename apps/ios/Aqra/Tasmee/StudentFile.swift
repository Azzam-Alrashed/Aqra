import Foundation

/// A teacher's file on one student: kept by the teacher, from what they themselves heard. It never holds the
/// student's own progress, which only the student's app reads.
struct StudentFile: Identifiable, Hashable {
    /// The student's uid.
    let id: String
    var name: String
    var lastHeardAt: Date
    /// The teacher's private notes.
    var notes: String

    init(id: String, name: String, lastHeardAt: Date, notes: String = "") {
        self.id = id
        self.name = name
        self.lastHeardAt = lastHeardAt
        self.notes = notes
    }

    init?(id: String, document: [String: Any]) {
        guard let name = document["name"] as? String else { return nil }
        self.init(id: id, name: name, lastHeardAt: document["lastHeardAt"] as? Date ?? .distantPast,
                  notes: document["notes"] as? String ?? "")
    }
}
