import DataKit
import Foundation

/// "Would you buy it again?" — the answer, in the sheet's words rather than
/// the column's (GLO-87).
///
/// GLO-87 left this open: is "would repurchase" a new status, a chip, or a
/// rendering of something that exists? It is the third. `user_items.status`
/// already carries `repurchased`, which is a fact about what you **did**;
/// `like_state` is the pre-ranking signal for what you **would**, and Sean's
/// own phrasing — "repurchased, would repurchase" — is exactly that pair. No
/// schema change, and the two never contradict each other because they are
/// answering different questions.
public enum RepurchaseAnswer: String, Sendable, CaseIterable {
    case yes, no
}

extension RepurchaseAnswer {
    /// Unanswered is `neutral`, not a missing row: the column is
    /// `-1 | 0 | 1` and 0 is what "I haven't said" looks like there. Keeping
    /// the mapping in one place means the sheet never has to know that.
    init?(_ state: LikeState) {
        switch state {
        case .liked: self = .yes
        case .disliked: self = .no
        case .neutral: return nil
        }
    }

    var state: LikeState {
        switch self {
        case .yes: .liked
        case .no: .disliked
        }
    }

    /// What to persist for an answer that has been cleared. Explicit because
    /// the alternative — deleting the row — would lose the difference between
    /// "asked and shrugged" and "never asked", and the aggregates read that
    /// difference.
    static func state(for answer: RepurchaseAnswer?) -> LikeState {
        answer?.state ?? .neutral
    }
}

/// How the sheet's repurchase control reaches persistence (GLO-87). Same shape
/// as `ShelfFitStore` and `ShelfChipStore`, for the same reasons: the model
/// tests against a recording stub, fixture states run with no store at all,
/// and the live wiring is one line per side.
///
/// Unlike `ShelfChipStore`, the live factory is real from the first commit —
/// `likeState(itemID:)` and `updateLikeState(itemID:to:)` both landed with
/// #192's opening, so there is no half-wired stage to defend.
public struct ShelfLikeStore: Sendable {
    public var load: @Sendable (_ itemID: UUID) async throws -> RepurchaseAnswer?
    public var save: @Sendable (_ itemID: UUID, _ answer: RepurchaseAnswer?) async throws -> Void

    public init(
        load: @escaping @Sendable (UUID) async throws -> RepurchaseAnswer?,
        save: @escaping @Sendable (UUID, RepurchaseAnswer?) async throws -> Void
    ) {
        self.load = load
        self.save = save
    }

    /// The live path: `user_items.like_state` through the frozen core,
    /// translated at this edge so the feature speaks in repurchase and the
    /// core keeps speaking in likes.
    public static func repository(_ repository: ShelfRepository) -> ShelfLikeStore {
        ShelfLikeStore(
            load: { itemID in
                // A nil read is "no row / never asked", which lands on the
                // same unanswered state as an explicit neutral — the control
                // shows nothing selected either way.
                guard let state = try await repository.likeState(itemID: itemID) else { return nil }
                return RepurchaseAnswer(state)
            },
            save: { itemID, answer in
                try await repository.updateLikeState(
                    itemID: itemID,
                    to: RepurchaseAnswer.state(for: answer)
                )
            }
        )
    }
}
