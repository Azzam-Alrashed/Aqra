import Foundation

// Friends and competitions as plain values, with no Firebase: each reads itself from a Firestore document's fields
// (dates already turned into `Date`) and writes itself back the same way, so every rule can be tested. See
// backend/README.md for the collections.

/// An invitation to be friends: a short code (and link) valid for a week.
struct FriendInvite: Identifiable, Hashable {
    /// The code: six characters from the same clear alphabet as a peer's tasmee' code.
    let id: String
    var ownerUid: String
    var ownerName: String
    var createdAt: Date
    var expiresAt: Date

    static let lifetime: TimeInterval = 7 * 86_400

    init(id: String, ownerUid: String, ownerName: String, createdAt: Date = .now,
         expiresAt: Date = .now.addingTimeInterval(FriendInvite.lifetime)) {
        self.id = id
        self.ownerUid = ownerUid
        self.ownerName = ownerName
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    init?(id: String, document: [String: Any]) {
        guard let ownerUid = document["ownerUid"] as? String, let expiresAt = document["expiresAt"] as? Date else { return nil }
        self.init(id: id, ownerUid: ownerUid, ownerName: document["ownerName"] as? String ?? "",
                  createdAt: document["createdAt"] as? Date ?? .distantPast, expiresAt: expiresAt)
    }

    var document: [String: Any] {
        ["ownerUid": ownerUid, "ownerName": ownerName, "createdAt": createdAt, "expiresAt": expiresAt]
    }

    func isValid(at date: Date = .now) -> Bool { expiresAt > date }

    var link: URL { URL(string: "aqra://friend/\(id)")! }
}

/// Two friends. The document's id is their two uids, sorted, joined by "_".
struct Friendship: Identifiable, Hashable {
    let id: String
    var members: [String]
    var names: [String: String]
    var createdAt: Date

    static func id(_ a: String, _ b: String) -> String {
        a < b ? "\(a)_\(b)" : "\(b)_\(a)"
    }

    init(id: String, members: [String], names: [String: String], createdAt: Date = .now) {
        self.id = id
        self.members = members
        self.names = names
        self.createdAt = createdAt
    }

    init?(id: String, document: [String: Any]) {
        guard let members = document["members"] as? [String], members.count == 2 else { return nil }
        self.init(id: id, members: members, names: document["names"] as? [String: String] ?? [:],
                  createdAt: document["createdAt"] as? Date ?? .distantPast)
    }

    func document(inviteCode: String) -> [String: Any] {
        ["members": members, "names": names, "inviteCode": inviteCode, "createdAt": createdAt]
    }

    /// The other friend, seen from one of them.
    func friend(of uid: String) -> (uid: String, name: String) {
        let other = members.first { $0 != uid } ?? uid
        return (other, names[other] ?? "")
    }
}

/// A competition: a race among friends, a group khatmah, or a teacher's competition among their students.
struct Competition: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case friends, khatmah, teacher
    }

    /// What the race counts. A khatmah counts parts; a teacher's competition, the pages the teacher heard clean.
    enum Metric: String, CaseIterable {
        case pagesRevised, daysRevised, ayatMemorized, parts, cleanPages
    }

    let id: String
    var kind: Kind
    var title: String
    var metric: Metric
    var ownerUid: String
    var ownerName: String
    var startsAt: Date
    var endsAt: Date
    var memberUids: [String]
    var createdAt: Date

    init(id: String, kind: Kind, title: String, metric: Metric, ownerUid: String, ownerName: String, startsAt: Date,
         endsAt: Date, memberUids: [String], createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.title = title
        self.metric = metric
        self.ownerUid = ownerUid
        self.ownerName = ownerName
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.memberUids = memberUids
        self.createdAt = createdAt
    }

    init?(id: String, document: [String: Any]) {
        guard let kind = (document["kind"] as? String).flatMap(Kind.init),
              let metric = (document["metric"] as? String).flatMap(Metric.init),
              let ownerUid = document["ownerUid"] as? String, let startsAt = document["startsAt"] as? Date,
              let endsAt = document["endsAt"] as? Date, let memberUids = document["memberUids"] as? [String] else { return nil }
        self.init(id: id, kind: kind, title: document["title"] as? String ?? "", metric: metric, ownerUid: ownerUid,
                  ownerName: document["ownerName"] as? String ?? "", startsAt: startsAt, endsAt: endsAt,
                  memberUids: memberUids, createdAt: document["createdAt"] as? Date ?? .distantPast)
    }

    var document: [String: Any] {
        ["kind": kind.rawValue, "title": title, "metric": metric.rawValue, "ownerUid": ownerUid, "ownerName": ownerName,
         "startsAt": startsAt, "endsAt": endsAt, "memberUids": memberUids, "createdAt": createdAt]
    }

    func isRunning(at date: Date = .now) -> Bool { startsAt <= date && date < endsAt }
}

/// A member's standing in a competition.
struct CompetitionMember: Identifiable, Hashable {
    /// The member's uid.
    let id: String
    var name: String
    var score: Int

    init(id: String, name: String, score: Int) {
        self.id = id
        self.name = name
        self.score = score
    }

    init?(id: String, document: [String: Any]) {
        self.init(id: id, name: document["name"] as? String ?? "", score: (document["score"] as? NSNumber)?.intValue ?? 0)
    }

    /// Members by score, highest first; ties share a rank and are ordered by name.
    static func ranked(_ members: [CompetitionMember]) -> [(rank: Int, member: CompetitionMember)] {
        let sorted = members.sorted { ($0.score, $1.name) > ($1.score, $0.name) }
        var result: [(Int, CompetitionMember)] = []
        for (index, member) in sorted.enumerated() {
            let rank = index > 0 && sorted[index - 1].score == member.score ? result[index - 1].0 : index + 1
            result.append((rank, member))
        }
        return result
    }
}

/// One of a group khatmah's thirty parts.
struct KhatmahPart: Identifiable, Hashable {
    /// The juz', 1…30.
    let id: Int
    var claimedBy: String?
    var claimedName: String
    var done: Bool

    init(id: Int, claimedBy: String? = nil, claimedName: String = "", done: Bool = false) {
        self.id = id
        self.claimedBy = claimedBy
        self.claimedName = claimedName
        self.done = done
    }

    init?(id: String, document: [String: Any]) {
        guard let juz = Int(id) else { return nil }
        self.init(id: juz, claimedBy: document["claimedBy"] as? String, claimedName: document["claimedName"] as? String ?? "",
                  done: document["done"] as? Bool ?? false)
    }

    var document: [String: Any] {
        ["claimedBy": claimedBy ?? NSNull(), "claimedName": claimedName, "done": done]
    }
}

/// A friends' race's score, from what the student did within its dates.
enum CompetitionScore {
    @MainActor
    static func score(_ metric: Competition.Metric, from start: Date, to end: Date, memorization: MemorizationStore,
                      revision: RevisionStore, calendar: Calendar = .current) -> Int {
        let within = { (date: Date) in date >= start && date < end }
        switch metric {
        case .pagesRevised: return revision.history.filter { within($0.date) }.count
        case .daysRevised:
            // Days revised are kept as the start of each day: the first day counts whatever hour the race began.
            let firstDay = calendar.startOfDay(for: start)
            return revision.revisedDays.filter { $0 >= firstDay && $0 < end }.count
        case .ayatMemorized: return memorization.ayahs.values.filter { $0.learnedAt.map(within) ?? false }.count
        case .parts, .cleanPages: return 0
        }
    }
}
