import DataKit
import Foundation
import Observation

/// The collection composer's state — GLO-21's remaining CRUD half, and the
/// `+` drawer's third door made real.
///
/// The shape is `RoutineComposerModel`'s deliberately, because the two screens
/// answer the same question from your shelf. **The one place they part is what
/// counts as finished**: a routine with no steps is a note rather than a
/// routine, so it refuses to save; a collection with no items is an empty
/// shelf you named on purpose, and the seed ships one (`want to try`, 0
/// products). So `canSave` here asks only for a name.
///
/// **This screen says nothing about who can see a collection.** It could —
/// `collections.visibility` is a real per-row column — and it deliberately
/// does not: `CollectionsRepository.create` takes no `visibility` argument
/// because "a create call that could also publish is a create call that
/// publishes by accident". The column defaults to `only_you`, which is what
/// this composer produces, and the profile's collections tab states that
/// ceiling from the rows themselves (GLO-261).
@MainActor
@Observable
public final class CollectionComposerModel {
    public var title = ""
    public var tint: CollectionTint?
    public private(set) var picked: [CollectionItem] = []
    /// The shelf to pick from, loaded once. A collection groups things you
    /// OWN — `collection_items.user_item_id` references `user_items` — so the
    /// picker reads your shelf and never the catalog.
    public private(set) var shelf: [CollectionItem] = []
    public private(set) var isLoadingShelf = true
    public private(set) var isSaving = false
    public private(set) var saveError: GlossedError?

    private let store: CollectionsStore?
    var task: Task<Void, Never>?

    public init(store: CollectionsStore? = nil) {
        self.store = store
    }

    public func loadShelf() {
        task?.cancel()
        guard let store else {
            isLoadingShelf = false
            return
        }
        task = Task {
            let rows = await (try? store.shelf()) ?? []
            guard !Task.isCancelled else { return }
            shelf = rows
            isLoadingShelf = false
        }
    }

    // MARK: - picking

    /// Tapping a shelf row toggles it. In appends to the end, which becomes
    /// its `position` — the order you tapped in is the order the collection
    /// draws, the same rule the routine composer follows.
    public func toggle(_ item: CollectionItem) {
        if let index = picked.firstIndex(where: { $0.id == item.id }) {
            picked.remove(at: index)
        } else {
            picked.append(item)
        }
    }

    public func isPicked(_ item: CollectionItem) -> Bool {
        picked.contains { $0.id == item.id }
    }

    // MARK: - save

    /// A name, and nothing else required. See the type comment for why this
    /// differs from the routine composer.
    public var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Creates the collection, then puts the picked items in it.
    ///
    /// **Two writes, and the second can fail on its own.** `create` mints the
    /// row; each `addItem` is a separate upsert. If the collection is made and
    /// an item does not go in, the collection EXISTS — so the screen closes
    /// rather than offering a retry that would mint a second one — and the
    /// caller is handed a warning naming what happened. Saying nothing would
    /// leave you with a collection quietly missing things you picked.
    ///
    /// `collectionID` is minted here and passed in, so a retry of the same
    /// intention cannot become two collections.
    public func save(onSaved: @escaping (_ warning: String?) -> Void) {
        guard canSave, !isSaving else { return }
        guard let store else {
            onSaved(nil)
            return
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = picked
        let chosenTint = tint
        isSaving = true
        saveError = nil
        task = Task {
            defer { isSaving = false }
            let collectionID = UUID()
            do {
                try await store.create(collectionID, name, chosenTint)
            } catch {
                guard !Task.isCancelled else { return }
                saveError = GlossedError.from(error)
                return
            }
            var missed = 0
            for (position, item) in items.enumerated() {
                do {
                    try await store.addItem(collectionID, item.id, position)
                } catch {
                    missed += 1
                }
            }
            guard !Task.isCancelled else { return }
            onSaved(missed == 0 ? nil : Self.partialWarning(name: name, missed: missed))
        }
    }

    /// Names the collection and the number, because "something went wrong" on
    /// a write that half-succeeded tells you nothing about what to do next.
    static func partialWarning(name: String, missed: Int) -> String {
        let n = "\(missed) product\(missed == 1 ? "" : "s")"
        return "made \(name), but \(n) didn't go in — open it from your profile to finish"
    }

    /// The footer's line: what saving will actually do.
    public var summary: String {
        guard canSave else { return "name it — the products are optional" }
        let n = picked.count
        let items = n == 0 ? "empty for now" : "\(n) product\(n == 1 ? "" : "s")"
        return tint.map { "\(items) · \($0.label)" } ?? items
    }
}
