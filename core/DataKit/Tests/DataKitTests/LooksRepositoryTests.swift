import Foundation
import Testing
@testable import DataKit

// Pure rules the looks repository encodes; the policies themselves are proven
// by pgTAP (looks.test.sql), which is the actual security boundary.

@Test func aDraftMintsItsOwnPrimaryKeyAndKeepsACallerSuppliedOne() {
    let one = LookDraft(caption: nil, photos: [], tags: [])
    let two = LookDraft(caption: nil, photos: [], tags: [])
    #expect(one.lookID != two.lookID)
    // …and a retry of the SAME draft is the same row, not a duplicate.
    let fixed = UUID()
    #expect(LookDraft(caption: nil, photos: [], tags: [], lookID: fixed).lookID == fixed)
}

@Test func rowEncodingsMatchTheMigrationsColumns() throws {
    // 0043's column names, spelled out — drift comes back as a server error
    // at best and a silently-ignored key at worst.
    let look = LooksRepository.LookRow(id: UUID(), userID: UUID(), caption: "c")
    let lookKeys = try keys(of: look)
    #expect(lookKeys == ["caption", "id", "user_id"])

    let photo = LooksRepository.PhotoRow(lookID: UUID(), r2Key: "k", position: 0)
    #expect(try keys(of: photo) == ["look_id", "position", "r2_key"])

    let tag = LooksRepository.TagRow(lookID: UUID(), variantID: UUID(), x: 0.5, y: 0.5)
    #expect(try keys(of: tag) == ["look_id", "variant_id", "x", "y"])
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
        id: lookID, caption: "glass skin", state: .draft,
        postedAt: nil, createdAt: Date()
    )
    // Deliberately shuffled — this is what a grouped rebuild can hand back.
    let photos = [
        LooksRepository.OwnPhotoRow(id: third, lookID: lookID, r2Key: "c", position: 2),
        LooksRepository.OwnPhotoRow(id: first, lookID: lookID, r2Key: "a", position: 0),
        LooksRepository.OwnPhotoRow(id: second, lookID: lookID, r2Key: "b", position: 1)
    ]

    let assembled = LooksRepository.assemble(looks: [look], photos: photos, tags: [])
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
            id: $0, caption: nil, state: .draft, postedAt: nil, createdAt: Date()
        )
    }
    let photos = [
        LooksRepository.OwnPhotoRow(id: UUID(), lookID: tuesday, r2Key: "tue", position: 0),
        LooksRepository.OwnPhotoRow(id: UUID(), lookID: monday, r2Key: "mon", position: 0)
    ]
    let tags = [
        LooksRepository.OwnTagRow(lookID: monday, variantID: mondayVariant, x: 0.1, y: 0.2),
        LooksRepository.OwnTagRow(lookID: tuesday, variantID: tuesdayVariant, x: 0.3, y: 0.4)
    ]

    let assembled = LooksRepository.assemble(looks: looks, photos: photos, tags: tags)
    #expect(assembled[0].photos.map(\.r2Key) == ["mon"])
    #expect(assembled[0].tags.map(\.variantID) == [mondayVariant])
    #expect(assembled[1].photos.map(\.r2Key) == ["tue"])
    #expect(assembled[1].tags.map(\.variantID) == [tuesdayVariant])
}

@Test func aLookWithNoPhotosAssemblesRatherThanDisappearing() {
    // `saveDraft` accepts an empty `photos`, so a photo-less draft is a real
    // state and the owner's list has to be able to draw it.
    let look = LooksRepository.OwnLookRow(
        id: UUID(), caption: nil, state: .draft, postedAt: nil, createdAt: Date()
    )
    let assembled = LooksRepository.assemble(looks: [look], photos: [], tags: [])
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
        id: UUID(), caption: nil, state: .publicState,
        postedAt: stamped, createdAt: Date()
    )
    let draft = LooksRepository.OwnLookRow(
        id: UUID(), caption: nil, state: .draft, postedAt: nil, createdAt: Date()
    )
    let assembled = LooksRepository.assemble(looks: [published, draft], photos: [], tags: [])
    #expect(assembled[0].isPublished)
    #expect(assembled[0].postedAt == stamped)
    #expect(assembled[1].isPublished == false)
    #expect(assembled[1].postedAt == nil)
}

private func encoded(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
}

private func keys(of value: some Encodable) throws -> [String] {
    try encoded(value).keys.sorted()
}
