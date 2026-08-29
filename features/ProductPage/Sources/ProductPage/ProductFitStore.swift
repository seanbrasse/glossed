import DataKit
import DesignSystem
import Foundation

/// How the product page's fit control reaches persistence (GLO-47's second
/// half).
///
/// The page shipped with its answer going nowhere, and the doc comment on
/// `anchorsHeld` said exactly why: *"the write exists but it needs a
/// `user_item_id`, and this page is opened from a variant."* That stopped
/// being true when #213 made the page reachable from the shelf — a
/// `ShelfItem`'s id **is** its `user_item_id` (`ShelfRowMapping` maps
/// `row.userItemID` straight into it), so the caller has had the missing
/// piece since that landed.
///
/// Its own type rather than `Shelf`'s `ShelfFitStore`, because features never
/// import features. Both translate the same two core calls at their own edge,
/// which is the cost of the layering rule.
///
/// The `Fit` ↔ `FitAnswer` mapping below is duplicated from `Shelf`'s, and
/// deliberately kept **private static functions rather than an extension on
/// `Fit`**: `Shelf` already declares `public extension Fit { init(answer:) }`,
/// and a second public one in a module the app imports alongside it would be
/// ambiguous at every call site in `app/`. The duplication wants a shared home
/// — `FitAnswer` lives in DesignSystem, which does not depend on DataKit, so
/// there is nowhere to put it without an architectural change. Filed as
/// GLO-164; until then both copies are pinned by exhaustive round-trip tests
/// so a divergence is a red test rather than a fit that silently never
/// persists.
public struct ProductFitStore: Sendable {
    public var load: @Sendable (_ userItemID: UUID) async throws -> Set<FitAnswer>
    public var save: @Sendable (_ userItemID: UUID, _ answers: Set<FitAnswer>) async throws -> Void

    public init(
        load: @escaping @Sendable (UUID) async throws -> Set<FitAnswer>,
        save: @escaping @Sendable (UUID, Set<FitAnswer>) async throws -> Void
    ) {
        self.load = load
        self.save = save
    }

    /// The live path: `item_fits` through the frozen core, the same pair the
    /// shelf sheet uses — `fits(itemID:)` reading, `captureFit` replacing
    /// wholesale.
    public static func repository(_ repository: ShelfRepository) -> ProductFitStore {
        ProductFitStore(
            load: { userItemID in
                try await Set(repository.fits(itemID: userItemID).map(ProductFitStore.answer))
            },
            save: { userItemID, answers in
                try await repository.captureFit(
                    itemID: userItemID,
                    fits: Set(answers.map(ProductFitStore.wire))
                )
            }
        )
    }

    /// A store for the debug picker: records nothing, returns nothing, and
    /// exists so a fixture state can still show the fit block now that the
    /// block is gated on being answerable (GLO-165). Not `nil`, because nil
    /// is how the real app says "this page cannot save" — a fixture is not
    /// making that claim, it is just not wired to a database.
    public static let picker = ProductFitStore(load: { _ in [] }, save: { _, _ in })

    /// The control's vocabulary as the column stores it. Case by case, so a
    /// new `fit_enum` value is a compile error here rather than an answer that
    /// silently never persists.
    static func wire(_ answer: FitAnswer) -> Fit {
        switch answer {
        case .justRight: .justRight
        case .tooLight: .tooLight
        case .tooDark: .tooDark
        case .tooPink: .tooPink
        case .tooYellow: .tooYellow
        case .tooOrange: .tooOrange
        }
    }

    static func answer(_ fit: Fit) -> FitAnswer {
        switch fit {
        case .justRight: .justRight
        case .tooLight: .tooLight
        case .tooDark: .tooDark
        case .tooPink: .tooPink
        case .tooYellow: .tooYellow
        case .tooOrange: .tooOrange
        }
    }
}
