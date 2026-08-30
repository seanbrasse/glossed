import Foundation

/// One collection as this feature reads it — the grid card's whole content.
///
/// `visibility` is deliberately NOT carried. `collections` has the column, but
/// V1 ships own-collections only and no surface here can honour, change, or
/// truthfully report it. A field on this struct is an invitation to write copy
/// about it, and copy about a scope no screen controls is the GLO-208 shape.
public struct CollectionSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let tint: CollectionTint?
    /// `N products` — a count of YOUR OWN collection, not a claim about
    /// people. It carries no cohort because there is no cohort: nothing here
    /// is evidence, so nothing here wears evidence chrome.
    public let itemN: Int

    public init(id: UUID, title: String, tint: CollectionTint?, itemN: Int) {
        self.id = id
        self.title = title
        self.tint = tint
        self.itemN = itemN
    }
}

/// One pickable/picked row. A collection groups things you **own** —
/// `collection_items.user_item_id` references `user_items`, so `id` is a
/// user-item id and a variant id would be refused by the foreign key. The
/// picker therefore reads your shelf, never the catalog.
public struct CollectionItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let brand: String

    public init(id: UUID, name: String, brand: String) {
        self.id = id
        self.name = name
        self.brand = brand
    }
}

/// The seams the app fills, as closures — the composer is driven and tested
/// with no repository present, and `CollectionsRepository` is injected by the
/// app layer. Features never import features, and this is why.
///
/// **`create` takes a caller-minted primary key.** The composer mints one id
/// at init and reuses it for every attempt, so a retry after a failed save
/// upserts the same row rather than minting a second collection with the same
/// name. `addItem`'s key is `(collection_id, user_item_id)`, so it is
/// re-runnable on the same terms — which together make the whole save
/// idempotent, and a partial failure safe to simply try again.
///
/// There is no `remove`. Sean scoped V1 as create · rename · add/remove
/// products, and a seam member with no surface is dead code; `deleted_at` is
/// waiting in the schema for the ticket that draws the screen.
public struct CollectionsStore: Sendable {
    public var mine: @Sendable () async throws -> [CollectionSummary]
    public var shelf: @Sendable () async throws -> [CollectionItem]
    public var items: @Sendable (_ collectionID: UUID) async throws -> [CollectionItem]
    public var create: @Sendable (_ collectionID: UUID, _ title: String, _ tint: CollectionTint?) async throws -> Void
    /// Writes the OWNER's column and nothing else. If a collection is ever
    /// shared, the title other people read comes from an approved
    /// `public_texts` row — a different write, on a different table, that
    /// this seam does not perform and no copy here may imply.
    public var rename: @Sendable (_ collectionID: UUID, _ title: String) async throws -> Void
    public var addItem: @Sendable (_ collectionID: UUID, _ itemID: UUID, _ position: Int) async throws -> Void
    public var removeItem: @Sendable (_ collectionID: UUID, _ itemID: UUID) async throws -> Void

    public init(
        mine: @escaping @Sendable () async throws -> [CollectionSummary],
        shelf: @escaping @Sendable () async throws -> [CollectionItem],
        items: @escaping @Sendable (UUID) async throws -> [CollectionItem],
        create: @escaping @Sendable (UUID, String, CollectionTint?) async throws -> Void,
        rename: @escaping @Sendable (UUID, String) async throws -> Void,
        addItem: @escaping @Sendable (UUID, UUID, Int) async throws -> Void,
        removeItem: @escaping @Sendable (UUID, UUID) async throws -> Void
    ) {
        self.mine = mine
        self.shelf = shelf
        self.items = items
        self.create = create
        self.rename = rename
        self.addItem = addItem
        self.removeItem = removeItem
    }
}
