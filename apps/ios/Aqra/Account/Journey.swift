import Foundation

/// The rest of the student's journey beside what's memorized and the revision record: the personal plan, the
/// rewards and the stages' assessments. Backed up together as one document, `users/{uid}/journey/state`.
@MainActor
final class Journey {
    let plan: PlanStore
    let rewards: RewardStore
    let assessments: AssessmentStore

    init(plan: PlanStore, rewards: RewardStore, assessments: AssessmentStore) {
        self.plan = plan
        self.rewards = rewards
        self.assessments = assessments
    }

    /// Called after any of them changes, so the backup can follow.
    var onChange: (() -> Void)? {
        didSet {
            plan.onChange = onChange
            rewards.onChange = onChange
            assessments.onChange = onChange
        }
    }

    struct Snapshot: Codable, Equatable {
        var plan = PlanStore.Snapshot.empty
        var rewards = RewardStore.Snapshot.empty
        var assessments = AssessmentStore.Snapshot.empty

        static let empty = Snapshot()

        static func merge(_ local: Snapshot, _ remote: Snapshot) -> Snapshot {
            Snapshot(plan: .merge(local.plan, remote.plan), rewards: .merge(local.rewards, remote.rewards),
                     assessments: .merge(local.assessments, remote.assessments))
        }
    }

    var snapshot: Snapshot {
        Snapshot(plan: plan.snapshot, rewards: rewards.snapshot, assessments: assessments.snapshot)
    }

    func apply(_ snapshot: Snapshot) {
        plan.apply(snapshot.plan)
        rewards.apply(snapshot.rewards)
        assessments.apply(snapshot.assessments)
    }
}
