import Foundation
import Testing
@testable import DataKit

// Pure rules the looks repository encodes; the policies themselves are proven
// by pgTAP (looks.test.sql), which is the actual security boundary.

@Test func aDraftMintsItsOwnPrimaryKeyAndKeepsACallerSuppliedOne() {
    let one = LookDraft(caption: nil, photos: [], spots: [])
    let two = LookDraft(caption: nil, photos: [], spots: [])
    #expect(one.lookID != two.lookID)
    // …and a retry of the SAME draft is the same row, not a duplicate. The
    // same rule now covers photos and spots, because 0049 made both of them
    // referenced-by-id: the draft mints every key it will ever write.
    let fixed = UUID()
    #expect(LookDraft(caption: nil, photos: [], spots: [], lookID: fixed).lookID == fixed)
    let photo = LookDraft.Photo(r2Key: "k", position: 0)
    let spot = LookDraft.Spot(photoID: photo.id, x: 0.5, y: 0.5, products: [])
    #expect(photo.id != spot.id)
}

@Test func rowEncodingsMatchTheMigrationsColumns() throws {
    // 0043's column names, spelled out — drift comes back as a server error
    // at best and a silently-ignored key at worst.
    let look = LooksRepository.LookRow(id: UUID(), userID: UUID(), caption: "c")
    let lookKeys = try keys(of: look)
    #expect(lookKeys == ["caption", "id", "user_id"])

    let photo = LooksRepository.PhotoRow(id: UUID(), lookID: UUID(), r2Key: "k", position: 0)
    #expect(try keys(of: photo) == ["id", "look_id", "position", "r2_key"])

    // 0049's shape: the spot carries the photo, the products ride separately.
    let spot = LooksRepository.TagSpotRow(id: UUID(), lookPhotoID: UUID(), x: 0.5, y: 0.5)
    #expect(try keys(of: spot) == ["id", "look_photo_id", "x", "y"])

    let variant = LooksRepository.TagVariantRow(lookTagID: UUID(), variantID: UUID(), position: 0)
    #expect(try keys(of: variant) == ["look_tag_id", "position", "variant_id"])
}

// The owner-side reads and the publish transition (GLO-230, GLO-238). `mine()`
// and `publish()` need a session and a database, so what is tested here is the
// part that can be wrong SILENTLY: assembly, ordering, and the exact shape of
// the publish payload. The policies and the column grants are proven by pgTAP,
// which is the actual security boundary.

@Test func photosComeBackInPositionOrderNoMatterWhatOrderTheyArriveIn() {
    // Written to fail first, and it did: without the sort in `assemble` the
    // photos came back in arrival order — the third photo FIRST. A look whose
    // photos draw in the wrong order is silently wrong rather than visibly
    // broken, and `look_photos` has its own `id` primary key, so nothing about
    // the storage order is positional.
    let lookID = UUID()
    let first = UUID(), second = UUID(), third = UUID()
    let look = LooksRepository.OwnLookRow(
        id: lookID, caption: "glass skin", state: .draft, visibility: .onlyYou,
        postedAt: nil, createdAt: Date()
    )
    // Deliberately shuffled — this is what a grouped rebuild can hand back.
    let photos = [
        LooksRepository.OwnPhotoRow(id: third, lookID: lookID, r2Key: "c", position: 2),
        LooksRepository.OwnPhotoRow(id: first, lookID: lookID, r2Key: "a", position: 0),
        LooksRepository.OwnPhotoRow(id: second, lookID: lookID, r2Key: "b", position: 1)
    ]

    let assembled = LooksRepository.assemble(looks: [look], photos: photos, tags: [], variants: [])
    #expect(assembled.count == 1)
    #expect(assembled[0].photos.map(\.r2Key) == ["a", "b", "c"])
    #expect(assembled[0].photoN == 3) // the n matches what is drawn
}

@Test func photosAndTagsDoNotLeakBetweenLooks() {
    // Two reads fetch children for every look at once; the grouping is the
    // only thing keeping yesterday's photo off today's look.
    let monday = UUID(), tuesday = UUID()
    let mondayVariant = UUID(), tuesdayVariant = UUID()
    let looks = [monday, tuesday].map {
        LooksRepository.OwnLookRow(
            id: $0, caption: nil, state: .draft, visibility: .onlyYou,
            postedAt: nil, createdAt: Date()
        )
    }
    let mondayPhoto = UUID(), tuesdayPhoto = UUID()
    let photos = [
        LooksRepository.OwnPhotoRow(id: tuesdayPhoto, lookID: tuesday, r2Key: "tue", position: 0),
        LooksRepository.OwnPhotoRow(id: mondayPhoto, lookID: monday, r2Key: "mon", position: 0)
    ]
    // Spots reach a look THROUGH its photo since 0049 — this grouping is what
    // keeps yesterday's spot off today's look, and the variants follow the
    // spot the same way.
    let mondayTag = UUID(), tuesdayTag = UUID()
    let tags = [
        LooksRepository.OwnTagRow(id: mondayTag, lookPhotoID: mondayPhoto, x: 0.1, y: 0.2),
        LooksRepository.OwnTagRow(id: tuesdayTag, lookPhotoID: tuesdayPhoto, x: 0.3, y: 0.4)
    ]
    let variants = [
        LooksRepository.OwnTagVariantRow(lookTagID: mondayTag, variantID: mondayVariant, position: 0),
        LooksRepository.OwnTagVariantRow(lookTagID: tuesdayTag, variantID: tuesdayVariant, position: 0)
    ]

    let assembled = LooksRepository.assemble(looks: looks, photos: photos, tags: tags, variants: variants)
    #expect(assembled[0].photos.map(\.r2Key) == ["mon"])
    #expect(assembled[0].spots.flatMap(\.products).map(\.variantID) == [mondayVariant])
    #expect(assembled[1].photos.map(\.r2Key) == ["tue"])
    #expect(assembled[1].spots.flatMap(\.products).map(\.variantID) == [tuesdayVariant])
}

@Test func aLookWithNoPhotosAssemblesRatherThanDisappearing() {
    // `saveDraft` accepts an empty `photos`, so a photo-less draft is a real
    // state and the owner's list has to be able to draw it.
    let look = LooksRepository.OwnLookRow(
        id: UUID(), caption: nil, state: .draft, visibility: .onlyYou,
        postedAt: nil, createdAt: Date()
    )
    let assembled = LooksRepository.assemble(looks: [look], photos: [], tags: [], variants: [])
    #expect(assembled.count == 1)
    #expect(assembled[0].photoN == 0)
    #expect(assembled[0].isPublished == false)
}

@Test func publishSendsTheStateColumnAndNothingElse() throws {
    // The load-bearing assertion of GLO-238's build half. `posted_at` is
    // stamped by the `looks_stamp_posted_at` trigger and was REVOKED from
    // `authenticated` by 0048 — sending it raises 42501, and so does
    // `updated_at`, which is absent from the update grant too. This is the
    // check that turns that into a Swift failure instead of a server one.
    let payload = try keys(of: LooksRepository.StateUpdate(state: .publicState))
    #expect(payload == ["state"])

    let object = try encoded(LooksRepository.StateUpdate(state: .publicState))
    #expect(object["state"] as? String == "public") // the enum's own spelling
}

@Test func theFourLookStatesCrossTheWireAsThePostgresEnumsOwnSpelling() {
    // `create type look_state as enum ('draft','pending_review','public','removed')`.
    // A label Postgres does not know is rejected, not coerced.
    #expect(LookState.allCases.map(\.rawValue) == ["draft", "pending_review", "public", "removed"])
}

@Test func onlyDraftAndPublicAreReachableFromTheApp() {
    // 0048's with-check pins a client write to `state in ('draft','public')`,
    // so `pending_review` and `removed` decode but cannot be produced here.
    // Publishing is unmoderated by decision (GLO-238) pending GLO-26 — this
    // asserts the payload the app can actually send, not a review step.
    #expect(LooksRepository.StateUpdate(state: .publicState).state == .publicState)
    #expect(LookState(rawValue: "pending_review") == .pendingReview) // decodes…
    #expect(LookState.publicState.rawValue == "public") // …and is never sent
}

@Test func postedAtRidesTheRowAndIsNeverWritten() {
    // The trigger stamps it on the way to `public` and clears it on the way
    // out, so a published look carries one and a draft does not. Carried on
    // `MyLook` because the card renders it; absent from every Encodable in
    // this repository because the client may not write it.
    let stamped = Date()
    let published = LooksRepository.OwnLookRow(
        id: UUID(), caption: nil, state: .publicState, visibility: .publicScope,
        postedAt: stamped, createdAt: Date()
    )
    let draft = LooksRepository.OwnLookRow(
        id: UUID(), caption: nil, state: .draft, visibility: .onlyYou,
        postedAt: nil, createdAt: Date()
    )
    let assembled = LooksRepository.assemble(looks: [published, draft], photos: [], tags: [], variants: [])
    #expect(assembled[0].isPublished)
    #expect(assembled[0].postedAt == stamped)
    #expect(assembled[1].isPublished == false)
    #expect(assembled[1].postedAt == nil)
}

@Test func theEditWritesSendExactlyTheirOneColumn() throws {
    // The StateUpdate discipline, applied to 0053's writes: `visibility`
    // rides its own column grant, and a payload that grew `state` alongside
    // it would turn "archive" into a silent unpost.
    #expect(try keys(of: LooksRepository.VisibilityUpdate(visibility: .friends)) == ["visibility"])
    let scope = try encoded(LooksRepository.VisibilityUpdate(visibility: .onlyYou))
    #expect(scope["visibility"] as? String == "only_you") // the enum's wire spelling

    // A cleared caption must SEND null — an omitted key leaves the column
    // untouched, and "remove the caption" would silently do nothing.
    #expect(try keys(of: LooksRepository.CaptionUpdate(caption: "hi")) == ["caption"])
    let cleared = try encoded(LooksRepository.CaptionUpdate(caption: nil))
    #expect(cleared.keys.sorted() == ["caption"])
    #expect(cleared["caption"] is NSNull)
}

@Test func archiveAndStateAreOrthogonalOnTheModel() {
    // Sean's ruling: archiving hides, unposting retracts, and neither implies
    // the other. `isPublished` answers POSTED, not READABLE — the readable
    // question needs `visibility` too, and pgTAP proves the composition
    // (per_item_visibility.test.sql).
    let archived = LooksRepository.OwnLookRow(
        id: UUID(), caption: nil, state: .publicState, visibility: .onlyYou,
        postedAt: Date(), createdAt: Date()
    )
    let assembled = LooksRepository.assemble(looks: [archived], photos: [], tags: [], variants: [])
    #expect(assembled[0].isPublished) // still posted…
    #expect(assembled[0].visibility == .onlyYou) // …just hidden
}

private func encoded(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
}

private func keys(of value: some Encodable) throws -> [String] {
    try encoded(value).keys.sorted()
}

@Test func productsInsideASpotComeBackInOverlayOrder() {
    // 0049: `position` orders the overlay, is deliberately NOT unique, and
    // ties break by variant_id. The sort lives in `assemble`, so it is
    // testable without a database — same reasoning as the photo sort above.
    let lookID = UUID(), photoID = UUID(), tagID = UUID()
    let look = LooksRepository.OwnLookRow(
        id: lookID, caption: nil, state: .draft, visibility: .onlyYou,
        postedAt: nil, createdAt: Date()
    )
    let photo = LooksRepository.OwnPhotoRow(id: photoID, lookID: lookID, r2Key: "a", position: 0)
    let tag = LooksRepository.OwnTagRow(id: tagID, lookPhotoID: photoID, x: 0.5, y: 0.5)
    let tied = [UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
    let variants = [
        LooksRepository.OwnTagVariantRow(lookTagID: tagID, variantID: tied[1], position: 1),
        LooksRepository.OwnTagVariantRow(lookTagID: tagID, variantID: UUID(), position: 0),
        LooksRepository.OwnTagVariantRow(lookTagID: tagID, variantID: tied[0], position: 1)
    ]

    let assembled = LooksRepository.assemble(looks: [look], photos: [photo], tags: [tag], variants: variants)
    let products = assembled[0].spots[0].products
    #expect(products.map(\.position) == [0, 1, 1])
    #expect(products[1].variantID == tied[0], "the tie breaks by variant_id")
    #expect(assembled[0].spots[0].photoID == photoID)
}

@Test func theSwapSendsTheKeyAloneSoATagCanNeverBeOrphanedByIt() throws {
    // 0054's shape: the row survives a swap — a payload that grew `id`,
    // `position` or `look_id` could repoint tags or reorder the carousel as
    // a side effect of changing bytes. One column, exactly.
    let payload = try keys(of: LooksRepository.PhotoKeySwap(r2Key: "users/u/looks/l/0-n.jpg"))
    #expect(payload == ["r2_key"])
}
