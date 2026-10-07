import Foundation

/// The rules of the stages, in one place so they can be tuned after trying them (docs/SRS.md, §3.7).
struct StagePolicy: Hashable, Sendable {
    /// An ayah is mastered once its half-life reaches this many days and its last revision was clean.
    var masteryStability = 60.0
    /// The share of a stage's ayat that must be memorized to pass it.
    var requiredMemorized = 1.0
    /// The share of a stage's ayat that must be mastered to pass it.
    var requiredMastered = 0.8
    /// The in-app test: how many questions, and the share answered right to pass.
    var testQuestions = 10
    var testPassScore = 0.8
    /// How long after a failed test it can be taken again.
    var retestCooldown: TimeInterval = 24 * 3_600
    /// Whether passing a stage needs a sheikh's test.
    var sheikhTestRequired = true
    /// A sheikh's test passes with at most this many mistakes per page heard; the teacher can change it per test.
    var allowedMistakesPerPage = 1

    static let standard = StagePolicy()
}

/// The curriculum's fixed structure (from the Etqan reference): ten stages of three juz' each. Stage k holds juz'
/// 3k−2…3k, and it's the k-th of the ten stairs drawn on the home.
enum Curriculum {
    static let stageCount = 10
    static let juzPerStage = 3

    static func juz(ofStage stage: Int) -> ClosedRange<Int> {
        let stage = min(max(stage, 1), stageCount)
        return (stage - 1) * juzPerStage + 1...stage * juzPerStage
    }

    static func stage(ofJuz juz: Int) -> Int {
        (min(max(juz, 1), 30) - 1) / juzPerStage + 1
    }
}
