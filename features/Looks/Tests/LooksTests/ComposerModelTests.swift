import Foundation
import Testing
@testable import Looks

// The composer against a recording stub — the TrendingStore/ShelfChips shape.

private func store(
    saveResult: Result<UUID, Error> = .success(UUID()),
    onSave: (@Sendable (String, [ComposerPhoto], [LookTagSpot]) -> Void)? = nil
) -> LooksStore {
    LooksStore(
        save: { caption, photos, spots in
            onSave?(caption, photos, spots)
            return try saveResult.get()
        },
        searchShelf: { _ in [] }
    )
}

private let png = Data([0x89, 0x50, 0x4E, 0x47])

/// Pins one product at (x, y) on `photoID` through the board — the only path
/// left after the one-shot `tag()` retired with migration 0049.
@MainActor
private func pin(
    _ model: ComposerModel, on photoID: UUID, label: String,
    variantID: UUID = UUID(), x: Double = 0.5, y: Double = 0.5
) {
    let frame = CGSize(width: 300, height: 300)
    let point = TagPoint(x: x, y: y)
    let crowded = model.tagBoard.spot(
        at: point.point(in: frame), in: frame, on: photoID,
        radius: LookTagGeometry.minimumSeparation
    )
    guard let spot = model.tagBoard.place(on: photoID, at: point, in: frame) ?? crowded?.id else {
        Issue.record("placement was refused")
        return
    }
    model.tagBoard.add(
        TaggedProduct(variantID: variantID, label: label, category: TagCategory(slug: "t", label: "t")),
        to: spot
    )
}

@MainActor
@Test func aLookIsAPhotoPostSoPostNeedsAPhoto() {
    let model = ComposerModel(store: store())
    #expect(!model.canPost, "no photo, no post — the caption is not the point")
    model.caption = "a caption alone"
    #expect(!model.canPost)
    model.addPhoto(png)
    #expect(model.canPost)
}

@MainActor
@Test func theCapIsEnforcedAtTheDoorNotDiscoveredAtTheExtreme() {
    let model = ComposerModel(store: store())
    for _ in 0 ..< ComposerModel.photoCap + 3 {
        model.addPhoto(png)
    }
    #expect(model.photos.count == ComposerModel.photoCap)
    #expect(!model.canAddPhoto)
    #expect(model.remainingPhotoSlots == 0)
    // positions stay dense and ordered
    #expect(model.photos.map(\.position) == Array(0 ..< ComposerModel.photoCap))
}

@MainActor
@Test func removingAPhotoRenumbersAndTakesThatPhotosTagsWithIt() {
    // **This assertion is inverted from what it used to say, deliberately.**
    // It read "tags pin to the look, not a photo" and asserted the tag
    // SURVIVED — which is exactly the gap GLO-266 names: a tag with
    // coordinates and no photo. A tag pins to a PHOTO now, so it goes when
    // the photo does.
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    model.addPhoto(png)
    let first = model.photos[0].id
    pin(model, on: first, label: "fenty 330", x: 0.4, y: 0.6)
    #expect(model.tagBoard.spots.count == 1)

    model.removePhoto(first)

    #expect(model.photos.map(\.position) == [0])
    #expect(model.tagBoard.spots.isEmpty, "coordinates into a photo that is gone are not a tag")
}

// MARK: - reorder (GLO-232)

@MainActor
@Test func movingAPhotoReordersItAndKeepsPositionsDense() {
    let model = ComposerModel(store: store())
    for _ in 0 ..< 4 {
        model.addPhoto(png)
    }
    let ids = model.photos.map(\.id)

    model.movePhoto(from: 3, to: 0)

    #expect(model.photos.map(\.id) == [ids[3], ids[0], ids[1], ids[2]])
    #expect(model.photos.map(\.position) == [0, 1, 2, 3], "dense from zero, and unique")
}

@MainActor
@Test func aReorderDoesNotDisturbTheTags() {
    // Moving photos around must leave the board exactly as it was — same
    // spots, same products, same pins — because a spot keys on its photo's
    // identity, never on its position.
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    model.addPhoto(png)
    model.addPhoto(png)
    let blush = UUID()
    pin(model, on: model.photos[0].id, label: "rare beauty soft pinch · joy", variantID: blush, x: 0.7, y: 0.6)
    pin(model, on: model.photos[1].id, label: "fenty pro filt'r · 330", x: 0.3, y: 0.4)
    let before = model.tagBoard

    model.movePhoto(from: 0, to: 2)
    model.movePhoto(from: 2, to: 1)

    // A spot keys on its photo's IDENTITY, not its position, so a reorder
    // cannot move a tag off the photo it was placed on.
    #expect(model.tagBoard == before, "reordering moves photos, never spots")
    #expect(model.tagBoard.placement(of: blush) != nil)
}

@MainActor
@Test func aMoveThenARemoveRenumbersThroughTheSameOnePath() {
    let model = ComposerModel(store: store())
    for _ in 0 ..< 4 {
        model.addPhoto(png)
    }
    let ids = model.photos.map(\.id)

    model.movePhoto(from: 0, to: 3)
    model.removePhoto(ids[2])

    #expect(model.photos.map(\.id) == [ids[1], ids[3], ids[0]])
    #expect(model.photos.map(\.position) == [0, 1, 2])
}

@MainActor
@Test func aMoveByIdIgnoresAPayloadThatIsNotOurs() {
    // The drop handler carries an identity off a drag pasteboard; a stale or
    // foreign one must move nothing rather than move something arbitrary.
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    model.addPhoto(png)
    let ids = model.photos.map(\.id)

    model.movePhoto(UUID(), to: 0)
    #expect(model.photos.map(\.id) == ids)

    model.movePhoto(ids[1], to: 0)
    #expect(model.photos.map(\.id) == [ids[1], ids[0]])
}

@MainActor
@Test func outOfRangeAndNoOpMovesLeaveTheOrderAlone() {
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    model.addPhoto(png)
    let ids = model.photos.map(\.id)

    model.movePhoto(from: 9, to: 0)
    model.movePhoto(from: -1, to: 1)
    model.movePhoto(from: 0, to: 0)
    #expect(model.photos.map(\.id) == ids)

    // A destination past the end clamps to the last slot rather than trapping.
    model.movePhoto(from: 0, to: 99)
    #expect(model.photos.map(\.id) == [ids[1], ids[0]])
    #expect(model.photos.map(\.position) == [0, 1])
}

@MainActor
@Test func theOrderTheUserSeesIsTheOrderThatSaves() async {
    // Positions are what 0043 stores, so the store must receive them in the
    // moved order — not the order the photos were added in.
    let seen = CapturedPositions()
    let model = ComposerModel(store: LooksStore(
        save: { _, photos, _ in
            await seen.set(photos.map(\.position))
            return UUID()
        },
        searchShelf: { _ in [] }
    ))
    for _ in 0 ..< 3 {
        model.addPhoto(png)
    }
    let last = model.photos[2].id
    model.movePhoto(from: 2, to: 0)

    model.post()
    await model.saveTask?.value

    #expect(model.photos[0].id == last)
    #expect(await seen.positions == [0, 1, 2])
}

@MainActor
@Test func reTaggingAVariantMovesThePinRatherThanStacking() {
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    let photo = model.photos[0].id
    let variant = UUID()
    pin(model, on: photo, label: "soft pinch", variantID: variant, x: 0.1, y: 0.1)
    pin(model, on: photo, label: "soft pinch", variantID: variant, x: 0.9, y: 0.9)
    // One place per variant — the board's rule, asserted here at the
    // composer's altitude because this is where a duplicate pick arrives.
    #expect(model.tagBoard.taggedProductCount == 1)
    let landed = model.tagBoard.placement(of: variant).flatMap { placement in
        model.tagBoard.spots.first { $0.id == placement.spotID }
    }
    #expect(landed?.point.x == 0.9, "the pin moved to the later spot rather than stacking")
}

private actor CapturedPositions {
    private(set) var positions: [Int] = []

    func set(_ positions: [Int]) {
        self.positions = positions
    }
}

@MainActor
@Test func linkTogglesAreRadioButtonsSince0054() {
    // "A look can have one collection, and one routine linked to it" —
    // picking another replaces, picking the same clears. The Set stays the
    // storage; these toggles are its only writers and cap it at one.
    let model = ComposerModel(store: nil)
    let am = UUID(), pm = UUID()
    model.toggleRoutine(am)
    #expect(model.linkedRoutineIDs == [am])
    model.toggleRoutine(pm)
    #expect(model.linkedRoutineIDs == [pm], "picking another REPLACES")
    model.toggleRoutine(pm)
    #expect(model.linkedRoutineIDs.isEmpty, "picking the same clears")
    let grails = UUID(), spring = UUID()
    model.toggleCollection(grails)
    model.toggleCollection(spring)
    #expect(model.linkedCollectionIDs == [spring])
}
