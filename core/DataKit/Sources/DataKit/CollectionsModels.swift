import Foundation

/// A collection's card tint. Mirrors the four tinted cards in `G.Profile`'s
/// collections grid — butter, cherry, mint, lilac.
///
/// An enum rather than the raw string because `collections.cover_tint` is
/// nullable `text` with **no check constraint** (probed, not assumed), so the
/// column will accept anything at all. Keeping the vocabulary on this side is
/// the only thing that stops a typo becoming an untinted card in production.
///
/// The wire values are the token names without the `--` and `-soft` the CSS
/// carries; DesignSystem owns the actual colour, and DataKit carries the fact.
public enum CollectionTint: String, Codable, Sendable, CaseIterable {
    case butter, cherry, mint, lilac
}

/// One of YOUR OWN collections, with the n its card renders.
///
/// A collection is a group of things you **own** — `docs/domain.md`: "User-created
/// group of UserItems with a cover". `collection_items.user_item_id` references
/// `user_items`, not `products` or `variants`, and the RLS `WITH CHECK` proves
/// it: the item must be yours. So a picker for this is built off the shelf, not
/// off catalog search.
public struct MyCollection: Sendable, Equatable, Identifiable {
    public let collectionID: UUID
    /// `collections.title` — the owner's copy. See `CollectionsRepository.rename`
    /// for why that is not the same string a stranger would read.
    public let title: String
    /// Nil for an untinted card, and **also** nil for a tint this build does
    /// not recognise. A card with an unknown tint still draws; a decode that
    /// threw would take the whole grid down over a cosmetic column.
    public let coverTint: CollectionTint?
    /// Defaults to `only_you` at the database (`scope_enum`). Nothing in V1
    /// widens it — creating a collection does not publish it.
    public let visibility: PrivacyScope
    /// The kit's `mono(c.count + ' products')`.
    ///
    /// **Counts only items the shelf still shows.** `collection_items` has no
    /// `deleted_at` of its own and a soft delete does not cascade, so a row
    /// whose `user_items.deleted_at` is set is still a membership row — and
    /// counting those would make a card claim "12 products" over a grid that
    /// draws nine.
    public let itemN: Int
    public let createdAt: Date

    public var id: UUID {
        collectionID
    }

    public init(
        collectionID: UUID, title: String, coverTint: CollectionTint?,
        visibility: PrivacyScope, itemN: Int, createdAt: Date
    ) {
        self.collectionID = collectionID
        self.title = title
        self.coverTint = coverTint
        self.visibility = visibility
        self.itemN = itemN
        self.createdAt = createdAt
    }
}
