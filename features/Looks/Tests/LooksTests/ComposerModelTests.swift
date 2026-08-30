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
