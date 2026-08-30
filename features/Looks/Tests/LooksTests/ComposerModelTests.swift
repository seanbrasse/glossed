import Foundation
import Testing
@testable import Looks

// The composer against a recording stub — the TrendingStore/ShelfChips shape.

private func store(
    saveResult: Result<UUID, Error> = .success(UUID()),
    onSave: (@Sendable (String, [ComposerPhoto], [ComposerTag]) -> Void)? = nil
) -> LooksStore {
    LooksStore(
        save: { caption, photos, tags in
            onSave?(caption, photos, tags)
            return try saveResult.get()
        },
        searchShelf: { _ in [] }
    )
}

private let png = Data([0x89, 0x50, 0x4E, 0x47])

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
    // positions stay dense and ordered
    #expect(model.photos.map(\.position) == Array(0 ..< ComposerModel.photoCap))
}

@MainActor
@Test func removingAPhotoRenumbersAndKeepsTheTags() {
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    model.addPhoto(png)
    model.tag(ShelfTagCandidate(variantID: UUID(), label: "fenty 330"), x: 0.4, y: 0.6)
    let first = model.photos[0].id
    model.removePhoto(first)
    #expect(model.photos.map(\.position) == [0])
    #expect(model.tags.count == 1, "tags pin to the look, not a photo")
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
    // The assertion this ticket is really about: tags pin to the LOOK, not
    // to a photo, so moving photos around must leave them exactly as they
    // were — same count, same variants, same pins.
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    model.addPhoto(png)
    model.addPhoto(png)
    let blush = UUID()
    model.tag(ShelfTagCandidate(variantID: blush, label: "rare beauty soft pinch · joy"), x: 0.7, y: 0.6)
    model.tag(ShelfTagCandidate(variantID: UUID(), label: "fenty pro filt'r · 330"), x: 0.3, y: 0.4)
    let before = model.tags

    model.movePhoto(from: 0, to: 2)
    model.movePhoto(from: 2, to: 1)

    #expect(model.tags == before, "tags pin to the look, not to a photo")
    #expect(model.tags.contains { $0.variantID == blush && $0.x == 0.7 && $0.y == 0.6 })
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
    let variant = UUID()
    model.tag(ShelfTagCandidate(variantID: variant, label: "soft pinch"), x: 0.1, y: 0.1)
    model.tag(ShelfTagCandidate(variantID: variant, label: "soft pinch"), x: 0.9, y: 0.9)
    #expect(model.tags.count == 1, "0043's primary key would reject the duplicate anyway")
    #expect(model.tags[0].x == 0.9)
}

@MainActor
@Test func pinCoordinatesClampToThePhoto() {
    let tag = ComposerTag(variantID: UUID(), label: "x", x: 1.7, y: -0.3)
    #expect(tag.x == 1.0)
    #expect(tag.y == 0.0)
}

@MainActor
@Test func aFailedSaveLosesNothingAndNamesItself() async {
    struct Offline: Error {}
    let model = ComposerModel(store: store(saveResult: .failure(Offline())))
    model.addPhoto(png)
    model.caption = "everything I typed"
    model.tag(ShelfTagCandidate(variantID: UUID(), label: "kept"), x: 0.5, y: 0.5)

    model.post()
    await model.saveTask?.value

    #expect(model.phase == .composing, "back to composing, not stuck saving")
    #expect(model.saveFailure != nil, "the failure names itself")
    #expect(model.caption == "everything I typed")
    #expect(model.photos.count == 1)
    #expect(model.tags.count == 1)
    #expect(model.canPost, "the retry is live")
}

@MainActor
@Test func aRetryAfterFailureCanSucceedAndClearsTheFailure() async {
    struct Offline: Error {}
    let flaky = FlakySaver()
    let model = ComposerModel(store: LooksStore(
        save: { _, _, _ in try await flaky.attempt() },
        searchShelf: { _ in [] }
    ))
    model.addPhoto(png)

    model.post()
    await model.saveTask?.value
    #expect(model.saveFailure != nil)

    model.post()
    await model.saveTask?.value
    guard case .saved = model.phase else {
        Issue.record("expected .saved after the retry")
        return
    }
    #expect(model.saveFailure == nil)
}

@MainActor
@Test func whatTheStoreReceivesIsWhatWasComposed() async {
    let received = Captured()
    let model = ComposerModel(store: LooksStore(
        save: { caption, photos, tags in
            await received.set(caption: caption, photoCount: photos.count, tagCount: tags.count)
            return UUID()
        },
        searchShelf: { _ in [] }
    ))
    model.addPhoto(png)
    model.addPhoto(png)
    model.caption = "the drafts of us"
    model.tag(ShelfTagCandidate(variantID: UUID(), label: "a"), x: 0.2, y: 0.2)

    model.post()
    await model.saveTask?.value

    #expect(await received.caption == "the drafts of us")
    #expect(await received.photoCount == 2)
    #expect(await received.tagCount == 1)
}

// MARK: - helpers

private actor FlakySaver {
    private var calls = 0
    struct Offline: Error {}

    func attempt() throws -> UUID {
        calls += 1
        if calls == 1 {
            throw Offline()
        }
        return UUID()
    }
}

private actor CapturedPositions {
    private(set) var positions: [Int] = []

    func set(_ positions: [Int]) {
        self.positions = positions
    }
}

private actor Captured {
    private(set) var caption = ""
    private(set) var photoCount = 0
    private(set) var tagCount = 0

    func set(caption: String, photoCount: Int, tagCount: Int) {
        self.caption = caption
        self.photoCount = photoCount
        self.tagCount = tagCount
    }
}
