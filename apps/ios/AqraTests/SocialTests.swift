import Foundation
import Testing
@testable import Aqra

/// Friends and competitions as values, and a race's score from what the student did — without the network.
@MainActor
struct SocialTests {
    private let start = Date(timeIntervalSince1970: 1_800_144_000)
    private func day(_ n: Int) -> Date { start.addingTimeInterval(Double(n) * 86_400 + 9 * 3_600) }

    @Test func friendsAndInvitesSurviveTheirDocuments() {
        #expect(Friendship.id("bob", "alice") == "alice_bob" && Friendship.id("alice", "bob") == "alice_bob")
        let friendship = Friendship(id: "alice_bob", members: ["alice", "bob"], names: ["alice": "Alice", "bob": "Bob"], createdAt: day(0))
        #expect(Friendship(id: "alice_bob", document: friendship.document(inviteCode: "ABC234")) == friendship)
        #expect(friendship.friend(of: "alice") == ("bob", "Bob") && friendship.friend(of: "bob") == ("alice", "Alice"))
        #expect(Friendship(id: "x", document: ["members": ["alice"]]) == nil)

        let invite = FriendInvite(id: "ABC234", ownerUid: "alice", ownerName: "Alice", createdAt: day(0), expiresAt: day(7))
        #expect(FriendInvite(id: "ABC234", document: invite.document) == invite)
        #expect(invite.isValid(at: day(6)) && !invite.isValid(at: day(8)))
        #expect(invite.link.absoluteString == "aqra://friend/ABC234")
    }

    @Test func competitionsSurviveTheirDocumentsAndRankTheirMembers() {
        let race = Competition(id: "c", kind: .friends, title: "رمضان", metric: .pagesRevised, ownerUid: "alice", ownerName: "Alice",
                               startsAt: day(0), endsAt: day(7), memberUids: ["alice", "bob"], createdAt: day(0))
        #expect(Competition(id: "c", document: race.document) == race)
        #expect(race.isRunning(at: day(3)) && !race.isRunning(at: day(8)))
        var broken = race.document
        broken["metric"] = "points"
        #expect(Competition(id: "c", document: broken) == nil)

        let ranked = CompetitionMember.ranked([
            CompetitionMember(id: "a", name: "Aisha", score: 12), CompetitionMember(id: "b", name: "Bilal", score: 30),
            CompetitionMember(id: "c", name: "Fatima", score: 12), CompetitionMember(id: "d", name: "Umar", score: 3),
        ])
        #expect(ranked.map(\.member.id) == ["b", "a", "c", "d"])
        #expect(ranked.map(\.rank) == [1, 2, 2, 4])

        let part = KhatmahPart(id: 5, claimedBy: "bob", claimedName: "Bob", done: true)
        #expect(KhatmahPart(id: "5", document: part.document) == part)
        #expect(KhatmahPart(id: "5", document: KhatmahPart(id: 5).document)?.claimedBy == nil)
    }

    @Test func aRacesScoreCountsOnlyWhatWasDoneWithinIt() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let memorization = MemorizationStore(fileURL: nil)
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        memorization.mark(7...20, memorized: true)
        for n in [0, 2, 2, 9] {
            revision.record(page: 2, ayahs: [7], stumbles: [], source: .app, memorization: memorization, now: day(n))
        }
        memorization.learn([30, 31, 32], at: day(1), stability: 2)
        memorization.learn([40], at: day(10), stability: 2)
        let score = { (metric: Competition.Metric) in
            CompetitionScore.score(metric, from: day(0), to: day(7), memorization: memorization, revision: revision, calendar: calendar)
        }
        #expect(score(.pagesRevised) == 3)
        #expect(score(.daysRevised) == 2)
        #expect(score(.ayatMemorized) == 3)
        #expect(score(.cleanPages) == 0)
    }
}
