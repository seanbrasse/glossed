import Foundation
import Testing
@testable import DataKit

// Pure rules the collections repository encodes. The policies themselves
// (collections_own, collection_items_own, collection_is_visible) are proven by
// the DB suite, which is the actual security boundary.

@Test func aCollectionsCountExcludesAnItemWhoseShelfEntryWasSoftDeleted() {
    // Written to fail first, and it did: counting membership rows returned 3
    // against a grid that draws 2. `collection_items` has no `deleted_at` of
    // its own and a soft delete does not cascade, so removing a lipstick from
    // your shelf leaves its membership row behind. A card claiming "3 products"
    // over two tiles is the failure this sort of count always produces.
    let collectionID = UUID()
    let kept = UUID(), alsoKept = UUID(), removedFromShelf = UUID()
    let collection = CollectionsRepository.OwnCollectionRow(
        id: collectionID, title: "spring", coverTint: "mint",
        visibility: .onlyYou, createdAt: Date()
    )
    let members = [kept, alsoKept, removedFromShelf].enumerated().map { index, item in
        CollectionsRepository.MemberRow(
            collectionID: collectionID, userItemID: item, position: index
        )
    }
    // `user_shelf_items` filters `deleted_at is null` itself, so the live set
    // is what that view answered with — the soft-deleted item is simply absent.
    let live: Set<UUID> = [kept, alsoKept]

    let assembled = CollectionsRepository.assemble(
        collections: [collection], members: members, live: live
    )
    #expect(assembled.count == 1)
    #expect(assembled[0].itemN == 2)
}

@Test func anUnrecognisedCoverTintIsNilRatherThanAThrownDecode() {
    // `collections.cover_tint` is nullable text with NO check constraint
    // (probed), so the column accepts anything. A card with an unknown tint
    // still draws; a throwing decode would take the whole grid down over a
    // cosmetic column.
    let rows = ["mint", "chartreuse", nil].map { tint in
        CollectionsRepository.OwnCollectionRow(
            id: UUID(), title: "t", coverTint: tint, visibility: .onlyYou, createdAt: Date()
        )
    }
    let assembled = CollectionsRepository.assemble(collections: rows, members: [], live: [])
    #expect(assembled[0].coverTint == .mint)
    #expect(assembled[1].coverTint == nil) // unrecognised, not fatal
    #expect(assembled[2].coverTint == nil)
}

@Test func theFourTintsAreTheKitsFourTintedCards() {
    // G.Profile's collections grid: --butter-soft, --cherry-soft, --mint-soft,
    // --lilac-soft. The enum is the whole vocabulary the column may hold.
    #expect(CollectionTint.allCases.map(\.rawValue) == ["butter", "cherry", "mint", "lilac"])
}

@Test func membersDoNotLeakBetweenCollections() {
    // One read fetches memberships for every collection at once; the grouping
    // is the only thing keeping spring's items out of summer's.
    let spring = UUID(), summer = UUID()
    let itemA = UUID(), itemB = UUID(), itemC = UUID()
    let collections = [spring, summer].map {
        CollectionsRepository.OwnCollectionRow(
            id: $0, title: "t", coverTint: nil, visibility: .onlyYou, createdAt: Date()
        )
    }
    let members = [
        CollectionsRepository.MemberRow(collectionID: summer, userItemID: itemC, position: 0),
        CollectionsRepository.MemberRow(collectionID: spring, userItemID: itemA, position: 0),
        CollectionsRepository.MemberRow(collectionID: spring, userItemID: itemB, position: 1)
    ]
    let assembled = CollectionsRepository.assemble(
        collections: collections, members: members, live: [itemA, itemB, itemC]
    )
    #expect(assembled[0].itemN == 2) // spring
    #expect(assembled[1].itemN == 1) // summer
}

@Test func anEmptyCollectionCountsZeroRatherThanDisappearing() {
    // A collection you just created has nothing in it, and the grid still has
    // to draw the card.
    let collection = CollectionsRepository.OwnCollectionRow(
        id: UUID(), title: "new", coverTint: "lilac", visibility: .onlyYou, createdAt: Date()
    )
    let assembled = CollectionsRepository.assemble(collections: [collection], members: [], live: [])
    #expect(assembled.count == 1)
    #expect(assembled[0].itemN == 0)
}

@Test func contentsComeBackInTheCollectionsOrderNotTheViewsOrder() {
    // `user_shelf_items` is a second read and answers in its own order, so the
    // membership positions have to be reapplied on this side.
    let collectionID = UUID()
    let first = UUID(), second = UUID(), third = UUID()
    let members = [
        CollectionsRepository.MemberRow(collectionID: collectionID, userItemID: first, position: 0),
        CollectionsRepository.MemberRow(collectionID: collectionID, userItemID: second, position: 1),
        CollectionsRepository.MemberRow(collectionID: collectionID, userItemID: third, position: 2)
    ]
    // Deliberately shuffled, as the view is free to answer.
    let rows = try? [third, first, second].map { try shelfRow(userItemID: $0) }

    let ordered = CollectionsRepository.ordered(rows ?? [], by: members)
    #expect(ordered.map(\.userItemID) == [first, second, third])
}

@Test func aShelfRowWithNoMembershipIsDroppedRatherThanAppended() {
    // Impossible by construction — the second read is filtered by the first's
    // ids — but appending an unpositioned row would put it somewhere arbitrary
    // rather than nowhere, which is the harder bug to see.
    let collectionID = UUID()
    let member = UUID(), stranger = UUID()
    let members = [
        CollectionsRepository.MemberRow(collectionID: collectionID, userItemID: member, position: 0)
    ]
    let rows = try? [member, stranger].map { try shelfRow(userItemID: $0) }

    let ordered = CollectionsRepository.ordered(rows ?? [], by: members)
    #expect(ordered.map(\.userItemID) == [member])
}

@Test func aBlankTitleIsRefusedRatherThanStored() throws {
    // `collections.title` is `not null` but carries no `check (length > 0)`
    // (probed), so an all-whitespace name would be accepted by Postgres and
    // leave an unaddressable card in the grid.
    #expect(throws: GlossedError.self) {
        _ = try CollectionsRepository.requireTitle("   \n ")
    }
    let trimmed = try CollectionsRepository.requireTitle("  spring  ")
    #expect(trimmed == "spring")
}

@Test func collectionRowEncodingsMatchTheMigrationsColumns() throws {
    // 0003's column names plus 0021's `visibility`, spelled out. Drift comes
    // back as a server error at best and a silently-ignored key at worst —
    // the failure mode that reads exactly like absence. This is the check that
    // would have caught the `client_id` column 0043 never had.
    let collection = try encodedKeys(of: CollectionsRepository.NewCollectionRow(
        id: UUID(), userID: UUID(), title: "spring", coverTint: "mint"
    ))
    #expect(collection == ["cover_tint", "id", "title", "user_id"])

    let member = try encodedKeys(of: CollectionsRepository.MemberWriteRow(
        collectionID: UUID(), userItemID: UUID(), position: 0
    ))
    #expect(member == ["collection_id", "position", "user_item_id"])

    // `collections` has no touch trigger (probed), so the rename ships
    // `updated_at` itself.
    let rename = try encodedKeys(of: CollectionsRepository.CollectionTitleUpdate(
        title: "summer", updatedAt: "2026-08-30T00:00:00Z"
    ))
    #expect(rename == ["title", "updated_at"])
}

@Test func aCollectionIsPrivateUntilSomethingElseSaysOtherwise() {
    // `collections.visibility` defaults to `only_you`, and NewCollectionRow
    // does not carry the column at all — a create call that could also publish
    // is a create call that publishes by accident. V1 ships no scope write.
    #expect(PrivacyScope.onlyYou.rawValue == "only_you")
    let keys = try? encodedKeys(of: CollectionsRepository.NewCollectionRow(
        id: UUID(), userID: UUID(), title: "t", coverTint: nil
    ))
    #expect(keys?.contains("visibility") == false)
}

// MARK: - helpers

/// Builds a `ShelfRow` through its decoder — its memberwise init is private
/// (`startedOnRaw`), so JSON is the only way in from a test.
private func shelfRow(userItemID: UUID) throws -> ShelfRow {
    let json: [String: Any] = [
        "user_item_id": userItemID.uuidString,
        "variant_id": UUID().uuidString,
        "product_id": UUID().uuidString,
        "product_name": "p",
        "brand_name": "b",
        "category_slug": "lipstick",
        "category_label": "lipstick",
        "domain": "makeup",
        "scope": "canonical",
        "status": "own",
        "logged_at": 0,
        "ranked_in_category": 0,
        "is_anchor": false
    ]
    let data = try JSONSerialization.data(withJSONObject: json)
    return try JSONDecoder().decode(ShelfRow.self, from: data)
}

private func encodedKeys(of value: some Encodable) throws -> [String] {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return (object ?? [:]).keys.sorted()
}
