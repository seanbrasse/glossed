import CoreGraphics
import Foundation
import Testing
@testable import Looks

// The composer holding a tag BOARD rather than a flat list (GLO-266). What is
// asserted here is the join: the board is the single source of truth, `tags`
// is a projection of it, and photo removal is the one place the new rule
// bites.

private func store() -> LooksStore {
    LooksStore(save: { _, _, _ in UUID() }, searchShelf: { _ in [] })
}

private let png = Data([0x89, 0x50, 0x4E, 0x47])
private let frame = CGSize(width: 300, height: 300)
private let lips = TagCategory(slug: "lipstick", label: "lipstick")
private let base = TagCategory(slug: "foundation", label: "foundation")

@MainActor
@Test func aSpotOnAPhotoHoldsSeveralProductsAndTheSaveSeesAllOfThem() {
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    let photo = model.photos[0].id
    guard let spot = model.tagBoard.place(on: photo, at: TagPoint(x: 0.4, y: 0.6), in: frame) else {
        Issue.record("placement was refused")
        return
    }
    model.tagBoard.add(TaggedProduct(variantID: UUID(), label: "dior lip glow", category: lips), to: spot)
    model.tagBoard.add(TaggedProduct(variantID: UUID(), label: "fenty 330", category: base), to: spot)

    #expect(model.tagBoard.taggedProductCount == 2)
    // The projection: one spot holding two products becomes two rows at the
    // same coordinates, because that is all `look_tags` can carry today.
    #expect(model.tags.count == 2)
    #expect(model.tags.allSatisfy { $0.x == 0.4 && $0.y == 0.6 })
}

@MainActor
@Test func theProjectionDropsWhichPhotoWhichIsTheGapItself() {
    // Two spots on two different photos project to four indistinguishable
    // (variant, x, y) rows. Nothing in `[ComposerTag]` says which photo, and
    // that is GLO-266's finding made concrete.
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    model.addPhoto(png)
    let first = model.photos[0].id
    let second = model.photos[1].id
    guard
        let onFirst = model.tagBoard.place(on: first, at: TagPoint(x: 0.5, y: 0.5), in: frame),
        let onSecond = model.tagBoard.place(on: second, at: TagPoint(x: 0.5, y: 0.5), in: frame)
    else {
        Issue.record("placement was refused")
        return
    }
    model.tagBoard.add(TaggedProduct(variantID: UUID(), label: "a", category: lips), to: onFirst)
    model.tagBoard.add(TaggedProduct(variantID: UUID(), label: "b", category: lips), to: onSecond)

    #expect(model.tags.count == 2)
    #expect(Set(model.tags.map(\.x)) == [0.5], "same coordinates, different photos, no way to tell")
    #expect(model.tagBoard.spots.count == 2, "the board still knows, and the schema does not")
}

@MainActor
@Test func removingOnePhotoTakesOnlyItsOwnTags() {
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    model.addPhoto(png)
    let first = model.photos[0].id
    let second = model.photos[1].id
    guard
        let onFirst = model.tagBoard.place(on: first, at: TagPoint(x: 0.2, y: 0.2), in: frame),
        let onSecond = model.tagBoard.place(on: second, at: TagPoint(x: 0.8, y: 0.8), in: frame)
    else {
        Issue.record("placement was refused")
        return
    }
    model.tagBoard.add(TaggedProduct(variantID: UUID(), label: "goes", category: lips), to: onFirst)
    model.tagBoard.add(TaggedProduct(variantID: UUID(), label: "stays", category: base), to: onSecond)

    model.removePhoto(first)

    #expect(model.tags.map(\.label) == ["stays"])
    #expect(model.tagBoard.spots.count == 1)
}

@MainActor
@Test func reorderingPhotosCannotMoveATagOffThePhotoItWasPlacedOn() {
    // A spot keys on its photo's IDENTITY, not its position — so this holds
    // for a better reason than it used to.
    let model = ComposerModel(store: store())
    for _ in 0 ..< 3 {
        model.addPhoto(png)
    }
    let last = model.photos[2].id
    guard let spot = model.tagBoard.place(on: last, at: TagPoint(x: 0.9, y: 0.1), in: frame) else {
        Issue.record("placement was refused")
        return
    }
    model.tagBoard.add(TaggedProduct(variantID: UUID(), label: "pinned", category: lips), to: spot)

    model.movePhoto(from: 2, to: 0)

    #expect(model.photos[0].id == last)
    #expect(model.tagBoard.placement(of: model.tagBoard.spots[0].products[0].variantID)?.photoID == last)
}

@MainActor
@Test func theListingReadsDownThePhotosInTheOrderTheUserSeesThem() {
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    model.addPhoto(png)
    let first = model.photos[0].id
    let second = model.photos[1].id
    guard
        let onSecond = model.tagBoard.place(on: second, at: TagPoint(x: 0.5, y: 0.5), in: frame),
        let onFirst = model.tagBoard.place(on: first, at: TagPoint(x: 0.5, y: 0.5), in: frame)
    else {
        Issue.record("placement was refused")
        return
    }
    model.tagBoard.add(TaggedProduct(variantID: UUID(), label: "on two", category: lips), to: onSecond)
    model.tagBoard.add(TaggedProduct(variantID: UUID(), label: "on one", category: lips), to: onFirst)

    #expect(model.tagListing.map(\.category.slug) == ["lipstick"])
    #expect(model.tagListing[0].entries.map(\.product.label) == ["on one", "on two"])

    // And it follows a reorder, because the listing is derived, not stored.
    model.movePhoto(from: 1, to: 0)
    #expect(model.tagListing[0].entries.map(\.product.label) == ["on two", "on one"])
}

@MainActor
@Test func theOneShotPathNeedsAPhotoBecauseATagIsASpotOnOne() {
    let model = ComposerModel(store: store())
    model.tag(ShelfTagCandidate(variantID: UUID(), label: "nothing to pin to"), x: 0.5, y: 0.5)
    #expect(model.tags.isEmpty, "no photo, no spot, no tag")

    model.addPhoto(png)
    model.tag(ShelfTagCandidate(variantID: UUID(), label: "lands on the first"), x: 0.5, y: 0.5)
    #expect(model.tags.count == 1)
    #expect(model.tagBoard.spots[0].photoID == model.photos[0].id)
}

@MainActor
@Test func untaggingByVariantFindsItWhereverItIsAndSweepsTheEmptyDot() {
    let model = ComposerModel(store: store())
    model.addPhoto(png)
    let variant = UUID()
    model.tag(ShelfTagCandidate(variantID: variant, label: "only one here"), x: 0.5, y: 0.5)
    #expect(model.tagBoard.spots.count == 1)

    model.removeTag(variant)

    #expect(model.tags.isEmpty)
    #expect(model.tagBoard.spots.isEmpty, "a dot with nothing behind it is not a tag")
}
