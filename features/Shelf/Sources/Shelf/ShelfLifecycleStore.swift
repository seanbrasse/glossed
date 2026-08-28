import DataKit
import Foundation

/// How the sheet's lifecycle actions reach persistence (GLO-72).
///
/// One closure per action, same shape as `ShelfFitStore` and for the same
/// reasons: the model tests against a recording stub, the picker's fixture
/// states run with no store at all, and the live wiring is one line.
///
/// `remove` is the half the frozen core already supplies. Status change
/// (`own → finished → repurchased …`) joins here when DataKit gains
/// `updateStatus(itemID:to:)` — that call needs a per-session core opening,
/// re-asked on GLO-72; building the closure now would fake a write path
/// that does not exist.
public struct ShelfLifecycleStore: Sendable {
    public var remove: @Sendable (UUID) async throws(GlossedError) -> Void

    public init(remove: @escaping @Sendable (UUID) async throws(GlossedError) -> Void) {
        self.remove = remove
    }

    /// The live path: soft delete through the frozen core. The shelf view
    /// filters `deleted_at is null`, so a removed item drops out of bays,
    /// list and counts on the next read — reversible in the schema, invisible
    /// in the app.
    public static func repository(_ repository: ShelfRepository) -> ShelfLifecycleStore {
        ShelfLifecycleStore(
            remove: { itemID throws(GlossedError) in
                try await repository.remove(itemID: itemID)
            }
        )
    }
}
