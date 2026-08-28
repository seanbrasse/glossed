import Foundation

/// Drives one ranking session: which comparison to ask next, what the answers
/// mean, and what to hand back for persisting.
///
/// It wraps `RankingEngine.Insertion` so the view never touches search state
/// directly — a view that can nudge `low`/`high` is a view that can invent a
/// preference nobody expressed.
public struct FaceOffSession: Equatable, Sendable {
    /// Everything the caller needs to persist the session.
    public struct Outcome: Equatable, Sendable {
        public let orderedItemIDs: [UUID]
        public let comparisons: [Answer]
        /// True when the cap stopped the search, so this ordering is our best
        /// guess rather than what the user stated. Callers may want to avoid
        /// treating it as strong evidence.
        public let isApproximate: Bool
    }

    /// One recorded answer, in the shape the persistence layer expects.
    public struct Answer: Equatable, Sendable {
        public let winnerItemID: UUID
        public let loserItemID: UUID
        public let skipped: Bool
    }

    public let categoryID: UUID
    public let categoryLabel: String
    private var insertion: RankingEngine.Insertion
    private(set) var answers: [Answer] = []

    public init(categoryID: UUID, categoryLabel: String, candidate: UUID, rankedItemIDs: [UUID]) {
        self.categoryID = categoryID
        self.categoryLabel = categoryLabel
        insertion = RankingEngine.Insertion(candidate: candidate, list: rankedItemIDs)
    }

    public var currentComparison: RankingEngine.Comparison? {
        insertion.nextComparison
    }

    public var isFinished: Bool {
        insertion.isSettled
    }

    public var answered: Int {
        answers.count
    }

    public var isApproximate: Bool {
        insertion.wasCapped
    }

    /// How many questions this session is likely to ask. Shown as "face-off 2
    /// of 3" so the end is visible — an open-ended sequence of questions is how
    /// ranking starts feeling like a chore.
    public var estimatedTotal: Int {
        let remaining = max(insertion.high - insertion.low, 1)
        let projected = answers.count + Int(ceil(log2(Double(remaining + 1))))
        return min(max(projected, answers.count + 1), RankingEngine.Insertion.maxComparisons)
    }

    public mutating func record(candidateWon: Bool) {
        guard let comparison = insertion.nextComparison else { return }
        insertion.record(candidateWon: candidateWon)
        answers.append(Answer(
            winnerItemID: candidateWon ? comparison.candidate : comparison.opponent,
            loserItemID: candidateWon ? comparison.opponent : comparison.candidate,
            skipped: false
        ))
    }

    /// "Too close to call". Recorded with an arbitrary winner and `skipped`
    /// true — the pair is data, the direction is not, and every consumer reads
    /// it through `scored_face_offs`, which drops skips.
    public mutating func skip() {
        guard let comparison = insertion.nextComparison else { return }
        insertion.skip()
        answers.append(Answer(
            winnerItemID: comparison.candidate,
            loserItemID: comparison.opponent,
            skipped: true
        ))
    }

    public var finalPosition: Int {
        insertion.resolvedIndex + 1
    }

    public var finalListLength: Int {
        insertion.list.count + 1
    }

    public func outcome() -> Outcome {
        Outcome(
            orderedItemIDs: insertion.result(),
            comparisons: answers,
            isApproximate: insertion.wasCapped
        )
    }
}
