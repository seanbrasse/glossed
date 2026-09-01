import DataKit
import Foundation

/// One collection as this feature reads it — the grid card's whole content.
public struct CollectionSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let tint: CollectionTint?
    /// `N products` — a count of YOUR OWN collection, not a claim about
    /// people. It carries no cohort because there is no cohort: nothing here
    /// is evidence, so nothing here wears evidence chrome.
    public let itemN: Int
    /// The owner's words on what this collection is (0054, batch 2). Nil is
    /// "never said" — the detail simply omits the line.
    public let description: String?
    /// Carried since the edit screen (GLO-272) — a scope a screen now
    /// CONTROLS. This struct deliberately omitted it before that, and the
    /// old reason still binds the copy: report it only where a control can
    /// honour it (the GLO-208 rule).
    public let visibility: PrivacyScope

    public init(
        id: UUID, title: String, tint: CollectionTint?, itemN: Int,
        description: String? = nil, visibility: PrivacyScope = .onlyYou
    ) {
        self.id = id
        self.title = title
        self.tint = tint
        self.itemN = itemN
        self.description = description
        self.visibility = visibility
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
    /// The edit screen's writes (GLO-272). `setVisibility` widening past
    /// only-you owes a `public_texts` submission the repository documents;
    /// `remove` is the soft delete — the grouping retracts, the items stay
    /// on the shelf.
    public var setVisibility: @Sendable (_ collectionID: UUID, _ scope: PrivacyScope) async throws -> Void
    /// Nil CLEARS (the repository encodes an explicit null).
    public var setDescription: @Sendable (_ collectionID: UUID, _ text: String?) async throws -> Void
    public var remove: @Sendable (_ collectionID: UUID) async throws -> Void

    public init(
        mine: @escaping @Sendable () async throws -> [CollectionSummary],
        shelf: @escaping @Sendable () async throws -> [CollectionItem],
        items: @escaping @Sendable (UUID) async throws -> [CollectionItem],
        create: @escaping @Sendable (UUID, String, CollectionTint?) async throws -> Void,
        rename: @escaping @Sendable (UUID, String) async throws -> Void,
        addItem: @escaping @Sendable (UUID, UUID, Int) async throws -> Void,
        removeItem: @escaping @Sendable (UUID, UUID) async throws -> Void,
        setVisibility: @escaping @Sendable (UUID, PrivacyScope) async throws -> Void = { _, _ in },
        setDescription: @escaping @Sendable (UUID, String?) async throws -> Void = { _, _ in },
        remove: @escaping @Sendable (UUID) async throws -> Void = { _ in }
    ) {
        self.mine = mine
        self.shelf = shelf
        self.items = items
        self.create = create
        self.rename = rename
        self.addItem = addItem
        self.removeItem = removeItem
        self.setVisibility = setVisibility
        self.setDescription = setDescription
        self.remove = remove
    }

    /// The live seam. It lives here rather than in `app/` because a feature
    /// may import `core` — and it did not exist at all until now, which is why
    /// this package shipped with a store, a tint, a summary type and **nothing
    /// joining any of it to `CollectionsRepository`**.
    ///
    /// `CollectionTint` is declared twice on purpose and bridged by raw value:
    /// DataKit owns the column's vocabulary and this feature owns the colour,
    /// and neither may import the other's. The bridge is total in both
    /// directions — the four cases are the same four — so an unmapped value
    /// means the two enums have drifted, and `parse` already answers `nil`
    /// for a word this build does not draw.
    public static func repository(
        collections: CollectionsRepository,
        shelf: ShelfRepository
    ) -> CollectionsStore {
        CollectionsStore(
            mine: {
                try await collections.mine().map {
                    CollectionSummary(
                        id: $0.collectionID,
                        title: $0.title,
                        tint: CollectionTint.parse($0.coverTint?.rawValue),
                        itemN: $0.itemN,
                        description: $0.description,
                        visibility: $0.visibility
                    )
                }
            },
            // A collection groups things you OWN, so the picker is your shelf
            // and never the catalog: `collection_items.user_item_id`
            // references `user_items`, and a variant id is refused by the
            // foreign key rather than silently stored.
            shelf: {
                try await shelf.shelf().map {
                    CollectionItem(
                        id: $0.userItemID, name: $0.productName, brand: $0.brandName
                    )
                }
            },
            items: { collectionID in
                try await collections.items(collectionID: collectionID).map {
                    CollectionItem(
                        id: $0.userItemID, name: $0.productName, brand: $0.brandName
                    )
                }
            },
            create: { collectionID, title, tint in
                _ = try await collections.create(
                    title: title,
                    tint: tint.flatMap { DataKit.CollectionTint(rawValue: $0.rawValue) },
                    collectionID: collectionID
                )
            },
            rename: { try await collections.rename(collectionID: $0, to: $1) },
            addItem: { try await collections.addItem(collectionID: $0, itemID: $1, position: $2) },
            removeItem: { try await collections.removeItem(collectionID: $0, itemID: $1) },
            setVisibility: { try await collections.setVisibility(collectionID: $0, to: $1) },
            setDescription: { try await collections.setDescription(collectionID: $0, to: $1) },
            remove: { try await collections.remove(collectionID: $0) }
        )
    }
}
