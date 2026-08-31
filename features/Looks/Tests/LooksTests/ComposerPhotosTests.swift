import Foundation
import Testing
@testable import Looks

// The photo cap and the multi-photo add (GLO-266): "Looks should allow adding
// multiple photos at once, with a limit of 5."
//
// Split from `ComposerModelTests` for the 300-line file ceiling, the house
// remedy the composer's own views already use. Nothing was renamed on the way
// across.

private func store() -> LooksStore {
    LooksStore(save: { _, _, _ in UUID() }, searchShelf: { _ in [] })
}

private let png = Data([0x89, 0x50, 0x4E, 0x47])

/// The number itself, asserted rather than left to whatever the constant
/// happens to say. GLO-266 quotes Sean: "a limit of 5". A test that only
/// reads `photoCap` back agrees with any value, including the six this
/// replaces.
@MainActor
@Test func theCapIsFiveBecauseSeanSaidFive() {
    #expect(ComposerModel.photoCap == 5)
}

// MARK: - several at once (GLO-266)

@MainActor
@Test func aSelectionArrivesWholeAndInTheOrderItWasPicked() {
    let model = ComposerModel(store: store())
    let picked = [Data([1]), Data([2]), Data([3])]

    #expect(model.addPhotos(picked) == 3)

    #expect(model.photos.map(\.localData) == picked, "picked order is post order")
    #expect(model.photos.map(\.position) == [0, 1, 2])
}

@MainActor
@Test func aSelectionBiggerThanTheRoomKeepsItsFrontAndDropsTheRest() {
    let model = ComposerModel(store: store())
    model.addPhoto(Data([0]))
    #expect(model.remainingPhotoSlots == ComposerModel.photoCap - 1)

    let tooMany = (1 ... ComposerModel.photoCap + 2).map { Data([UInt8($0)]) }
    let taken = model.addPhotos(tooMany)

    #expect(taken == ComposerModel.photoCap - 1, "as many as fit, and it says how many")
    #expect(model.photos.count == ComposerModel.photoCap)
    #expect(model.photos.map(\.position) == Array(0 ..< ComposerModel.photoCap))
    #expect(
        model.photos.dropFirst().map(\.localData) == Array(tooMany.prefix(ComposerModel.photoCap - 1)),
        "the front of the selection survives — it is what the user reached for first"
    )
}

@MainActor
@Test func aSelectionAtTheCapIsRefusedWholeRatherThanPartly() {
    let model = ComposerModel(store: store())
    model.addPhotos((0 ..< ComposerModel.photoCap).map { Data([UInt8($0)]) })
    let atCap = model.photos

    #expect(model.addPhotos([Data([9]), Data([10])]) == 0)
    #expect(model.photos == atCap, "nothing moved, nothing renumbered")
}

@MainActor
@Test func anEmptySelectionIsANoOpNotAnEmptyPhoto() {
    // A picker dismissed without a pick hands back an empty array; that must
    // not mint a zero-byte tile the strip would then render as a broken one.
    let model = ComposerModel(store: store())
    #expect(model.addPhotos([]) == 0)
    #expect(model.photos.isEmpty)
    #expect(!model.canPost)
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
