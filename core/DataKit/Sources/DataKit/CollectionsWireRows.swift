import Foundation

// The collections' wire formats and the pure rules built on them. Split from
// `CollectionsRepository.swift` for the 300-line ceiling; same split
// `ShelfWireRows.swift` is.

extension CollectionsRepository {
    struct OwnCollectionRow: Decodable, Sendable {
        let id: UUID
        let title: String
        /// Decoded as the raw string, never straight into `CollectionTint`.
        /// The column has no check constraint (probed), so an unrecognised
        /// value is possible — and a throwing decode would take the whole
        /// grid down over a cosmetic column.
        let coverTint: String?
        let visibility: PrivacyScope
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title, visibility
            case coverTint = "cover_tint"
            case createdAt = "created_at"
        }
    }

    struct MemberRow: Decodable, Sendable {
        let collectionID: UUID
        let userItemID: UUID
        let position: Int

        enum CodingKeys: String, CodingKey {
            case collectionID = "collection_id"
            case userItemID = "user_item_id"
            case position
        }
    }

    struct MemberWriteRow: Encodable, Sendable {
        let collectionID: UUID
        let userItemID: UUID
        let position: Int

        enum CodingKeys: String, CodingKey {
            case collectionID = "collection_id"
            case userItemID = "user_item_id"
            case position
        }
    }

    struct NewCollectionRow: Encodable, Sendable {
        let id: UUID
        let userID: UUID
        let title: String
        let coverTint: String?

        enum CodingKeys: String, CodingKey {
            case id, title
            case userID = "user_id"
            case coverTint = "cover_tint"
        }
    }

    /// `collections` carries no touch trigger (probed — `pg_trigger` is empty
    /// for it), so a rename that did not set `updated_at` would leave the row
    /// claiming it was last changed at creation.
    struct CollectionScopeUpdate: Encodable, Sendable {
        let visibility: PrivacyScope
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case visibility
            case updatedAt = "updated_at"
        }
    }

    struct CollectionTitleUpdate: Encodable, Sendable {
        let title: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case title
            case updatedAt = "updated_at"
        }
    }

    struct LiveItemRow: Decodable, Sendable {
        let userItemID: UUID

        enum CodingKeys: String, CodingKey {
            case userItemID = "user_item_id"
        }
    }

    struct InsertedID: Decodable, Sendable {
        let id: UUID
    }

    /// Pure assembly, so the counting rule is testable without a database.
    ///
    /// **`itemN` counts only members whose shelf entry is still live.**
    /// `collection_items` has no `deleted_at` and a soft delete does not
    /// cascade, so removing a lipstick from your shelf leaves its membership
    /// row behind. Counting membership rows would make the card claim "12
    /// products" over a grid that draws nine — the card's n and the card's
    /// contents have to come from the same fact.
    ///
    /// An unrecognised `cover_tint` becomes nil rather than throwing.
    static func assemble(
        collections: [OwnCollectionRow], members: [MemberRow], live: Set<UUID>
    ) -> [MyCollection] {
        let byCollection = Dictionary(grouping: members, by: \.collectionID)
        return collections.map { collection in
            let drawn = (byCollection[collection.id] ?? []).filter { live.contains($0.userItemID) }
            return MyCollection(
                collectionID: collection.id,
                title: collection.title,
                coverTint: collection.coverTint.flatMap(CollectionTint.init(rawValue:)),
                visibility: collection.visibility,
                itemN: drawn.count,
                createdAt: collection.createdAt
            )
        }
    }

    /// Puts the shelf rows into the collection's own order.
    ///
    /// Sorted here even though the membership query ordered them:
    /// `user_shelf_items` is a second read and answers in its own order, so the
    /// positions have to be reapplied on this side. A row with no membership
    /// is impossible by construction and dropped rather than appended.
    static func ordered(_ rows: [ShelfRow], by members: [MemberRow]) -> [ShelfRow] {
        var positions: [UUID: Int] = [:]
        for member in members {
            positions[member.userItemID] = member.position
        }
        return rows
            .compactMap { row in positions[row.userItemID].map { (position: $0, row: row) } }
            // Ties broken by id so the order is deterministic — `position`
            // defaults to 0, so a collection built without explicit positions
            // is entirely ties.
            .sorted { ($0.position, $0.row.userItemID.uuidString) < ($1.position, $1.row.userItemID.uuidString) }
            .map(\.row)
    }

    /// An all-whitespace title is rejected rather than stored: the column is
    /// `not null` but carries no `check (length > 0)` (probed), and a
    /// collection with a blank name is unaddressable in a grid.
    static func requireTitle(_ title: String) throws(GlossedError) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GlossedError(
                .invalidInput,
                userMessage: "give it a name.",
                debugDetail: "blank collection title"
            )
        }
        return trimmed
    }
}
