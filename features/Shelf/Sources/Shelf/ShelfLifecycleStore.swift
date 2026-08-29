import DataKit
import Foundation

/// How the sheet's lifecycle actions reach persistence (GLO-72).
///
/// One closure per action, same shape as `ShelfFitStore` and for the same
/// reasons: the model tests against a recording stub, the picker's fixture
/// states run with no store at all, and the live wiring is one line.
///
/// Both halves are real now: `remove` was always in the frozen core, and
/// `updateStatus(itemID:to:)` arrived with the session-7 opening (#147).
public struct ShelfLifecycleStore: Sendable {
    public var remove: @Sendable (UUID) async throws(GlossedError) -> Void
    public var updateStatus: @Sendable (UUID, ItemStatus) async throws(GlossedError) -> Void

    public init(
        remove: @escaping @Sendable (UUID) async throws(GlossedError) -> Void,
        updateStatus: @escaping @Sendable (UUID, ItemStatus) async throws(GlossedError) -> Void
    ) {
        self.remove = remove
        self.updateStatus = updateStatus
    }

    /// The live path. Remove is a soft delete — the shelf view filters
    /// `deleted_at is null`, so a removed item drops out of bays, list and
    /// counts on the next read. Status writes `user_items.status` and touches
    /// nothing else — a removed or re-statused ranked item's `rank_positions`
    /// row survives until the next ranking rewrite, by decision (GLO-72:
    /// hidden immediately, compacted at the next rewrite).
    public static func repository(_ repository: ShelfRepository) -> ShelfLifecycleStore {
        ShelfLifecycleStore(
            remove: { itemID throws(GlossedError) in
                try await repository.remove(itemID: itemID)
            },
            updateStatus: { itemID, status throws(GlossedError) in
                try await repository.updateStatus(itemID: itemID, to: status)
            }
        )
    }
}
