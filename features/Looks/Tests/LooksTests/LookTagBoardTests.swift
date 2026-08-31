import CoreGraphics
import Foundation
import Testing
@testable import Looks

// The tag value type (GLO-266). Four decisions live in `LookTagBoard` and all
// four are asserted here without a view or a database: placement,
// hit-testing, the cross-photo lookup and the category ordering.

private let photoOne = UUID()
private let photoTwo = UUID()
/// A landscape frame on purpose: normalized distance would be wrong on it,
/// and several assertions below only bite because it is not square.
private let frame = CGSize(width: 300, height: 200)

private let foundation = TagCategory(slug: "foundation", label: "foundation")
private let blush = TagCategory(slug: "blush", label: "blush")

/// `place` is `mutating`, and neither `#expect` nor `#require` can hold a
/// mutating call — so placements go through here, where a refusal records an
/// issue instead of force-unwrapping or trapping.
private func place(_ board: inout LookTagBoard, on photoID: UUID, at point: TagPoint) -> UUID {
    guard let id = board.place(on: photoID, at: point, in: frame) else {
        Issue.record("placement at \(point) on \(photoID) was refused")
        return UUID()
    }
    return id
}

private func product(_ label: String, _ category: TagCategory, id: UUID = UUID()) -> TaggedProduct {
    TaggedProduct(variantID: id, label: label, category: category)
}

// MARK: - the point

@Test func aPointClampsToThePhotoAndSurvivesTheRoundTrip() {
    #expect(TagPoint(x: 1.7, y: -0.3) == TagPoint(x: 1, y: 0))
    let middle = TagPoint(x: 0.25, y: 0.75)
    #expect(middle.point(in: frame) == CGPoint(x: 75, y: 150))
    #expect(TagPoint.of(CGPoint(x: 75, y: 150), in: frame) == middle)
}

@Test func aFrameThatHasNotMeasuredYetAnswersTheCentreNotNaN() {
    let placed = TagPoint.of(CGPoint(x: 10, y: 10), in: .zero)
    #expect(placed == TagPoint(x: 0.5, y: 0.5))
}

@Test func distanceIsInPointsBecauseNormalizedDistanceLiesOnANonSquarePhoto() {
    let left = TagPoint(x: 0.1, y: 0.5)
    let right = TagPoint(x: 0.2, y: 0.5)
    let top = TagPoint(x: 0.1, y: 0.4)
    // 0.1 across a 300pt photo is 30pt; 0.1 down a 200pt one is 20pt. The same
    // normalized delta, two different distances — which is the whole reason
    // hit-testing takes a size.
    #expect(left.distance(to: right, in: frame) == 30)
    #expect(left.distance(to: top, in: frame) == 20)
}

// MARK: - a spot holds several products

@Test func aSpotHoldsSeveralProductsInTheOrderTheyWereAdded() {
    var spot = LookTagSpot(photoID: photoOne, point: TagPoint(x: 0.5, y: 0.5))
    #expect(spot.isEmpty)
    let first = product("fenty pro filt'r · 330", foundation)
    let second = product("rare beauty soft pinch · joy", blush)

    // Assigned first: `#expect` captures its operand immutably, so a mutating
    // call cannot live inside the macro.
    let grewOnFirst = spot.add(first)
    let grewOnSecond = spot.add(second)
    let grewOnRepeat = spot.add(first)
    #expect(grewOnFirst)
    #expect(grewOnSecond)
    #expect(!grewOnRepeat, "already here — the set does not grow")

    #expect(spot.products.map(\.label) == [first.label, second.label])
    #expect(spot.holds(second.variantID))
}

@Test func aSpotsCountLineIsAPageIndicatorNotASampleSize() {
    // GLO-196: a look post is attributed content, never a claim. One product
    // gets NO line at all — a bare "1 products" would be chrome pretending to
    // be a count of something.
    var spot = LookTagSpot(photoID: photoOne, point: TagPoint(x: 0.5, y: 0.5))
    spot.add(product("a", blush))
    #expect(spot.countLine == nil)
    spot.add(product("b", foundation))
    spot.add(product("c", foundation))
    #expect(spot.countLine == "3 products")
}

// MARK: - placement

@Test func placingPutsAnEmptySpotWhereTheUserTapped() {
    var board = LookTagBoard()
    let id = place(&board, on: photoOne, at: TagPoint(x: 0.2, y: 0.3))
    #expect(board.spots(on: photoOne).count == 1)
    #expect(board.spot(id)?.isEmpty == true, "empty until the search bar answers")
    #expect(board.isEmpty, "an empty spot tags no product")
}

@Test func twoDotsAThumbCannotSeparateAreRefusedRatherThanStacked() {
    var board = LookTagBoard()
    let first = board.place(on: photoOne, at: TagPoint(x: 0.5, y: 0.5), in: frame)
    #expect(first != nil)
    // 3pt away in the rendered frame — inside the 44pt separation.
    let tooClose = board.place(on: photoOne, at: TagPoint(x: 0.51, y: 0.5), in: frame)
    #expect(tooClose == nil)
    #expect(board.spots.count == 1)

    // The same coordinates on a DIFFERENT photo are not crowded at all.
    #expect(board.place(on: photoTwo, at: TagPoint(x: 0.51, y: 0.5), in: frame) != nil)
    #expect(board.spots.count == 2)
}

@Test func anAbandonedPlacementIsSweptRatherThanLeftAsADotWithNothingBehindIt() {
    var board = LookTagBoard()
    _ = board.place(on: photoOne, at: TagPoint(x: 0.2, y: 0.2), in: frame)
    board.discardEmptySpots()
    #expect(board.spots.isEmpty)
}

@Test func removingAPhotoTakesItsTagsWithIt() {
    // The half a look-scoped tag could not do: coordinates into a photo that
    // no longer exists are not a tag.
    var board = LookTagBoard()
    let one = place(&board, on: photoOne, at: TagPoint(x: 0.2, y: 0.2))
    let two = place(&board, on: photoTwo, at: TagPoint(x: 0.8, y: 0.8))
    board.add(product("a", blush), to: one)
    board.add(product("b", foundation), to: two)

    board.removeSpots(on: photoOne)

    #expect(board.spots.map(\.id) == [two])
    #expect(board.taggedProductCount == 1)
}

// MARK: - hit-testing

@Test func aTapAnswersTheNearestDotNotTheFirstOneTagged() {
    var board = LookTagBoard()
    let far = place(&board, on: photoOne, at: TagPoint(x: 0.4, y: 0.5))
    let near = place(&board, on: photoOne, at: TagPoint(x: 0.6, y: 0.5))
    board.add(product("a", blush), to: far)
    board.add(product("b", foundation), to: near)

    // 174pt across: 6pt from `near` (180pt), 54pt from `far` (120pt).
    let hit = board.spot(at: CGPoint(x: 174, y: 100), in: frame, on: photoOne)
    #expect(hit?.id == near, "nearest, so the answer does not depend on tagging order")
}

@Test func aTapNowhereNearADotAnswersNothing() {
    var board = LookTagBoard()
    let spot = place(&board, on: photoOne, at: TagPoint(x: 0.1, y: 0.1))
    board.add(product("a", blush), to: spot)

    #expect(board.spot(at: CGPoint(x: 280, y: 190), in: frame, on: photoOne) == nil)
    // And a dot on another photo is not reachable from this one.
    #expect(board.spot(at: CGPoint(x: 30, y: 20), in: frame, on: photoTwo) == nil)
}

// MARK: - the cross-photo lookup

@Test func aVariantIsTaggedInExactlyOnePlaceSoTheLookupIsUnambiguous() {
    // Sean: "clicking a product in the list that is tagged in a different
    // photo than the current will scroll to that photo and then show the tag."
    // That instruction only has one answer if a variant lives in one spot.
    var board = LookTagBoard()
    let onOne = place(&board, on: photoOne, at: TagPoint(x: 0.2, y: 0.2))
    let onTwo = place(&board, on: photoTwo, at: TagPoint(x: 0.8, y: 0.8))
    let moved = product("fenty pro filt'r · 330", foundation)
    board.add(moved, to: onOne)
    board.add(product("rare beauty soft pinch · joy", blush), to: onOne)

    #expect(board.placement(of: moved.variantID) == TagPlacement(spotID: onOne, photoID: photoOne))

    board.add(moved, to: onTwo)

    #expect(
        board.placement(of: moved.variantID) == TagPlacement(spotID: onTwo, photoID: photoTwo),
        "tagging it elsewhere MOVES it"
    )
    #expect(board.taggedProductCount == 2, "moved, not copied")
    #expect(board.spot(onOne)?.products.count == 1, "the other product stayed put")
}

@Test func aSpotEmptiedByAMoveIsDiscardedButOneEmptiedByHandIsNot() {
    var board = LookTagBoard()
    let onOne = place(&board, on: photoOne, at: TagPoint(x: 0.2, y: 0.2))
    let onTwo = place(&board, on: photoTwo, at: TagPoint(x: 0.8, y: 0.8))
    let only = product("only one here", blush)
    board.add(only, to: onOne)
    board.add(product("keeps two alive", foundation), to: onTwo)

    board.add(only, to: onTwo)
    #expect(board.spot(onOne) == nil, "nothing behind that dot any more")

    // Untagging by hand keeps the spot — the user is usually about to refill it.
    board.remove(only.variantID, from: onTwo)
    #expect(board.spot(onTwo) != nil)
    #expect(board.spot(onTwo)?.products.count == 1)
}

@Test func anUnknownSpotIdIsRefusedRatherThanTrapping() {
    var board = LookTagBoard()
    let added = board.add(product("a", blush), to: UUID())
    #expect(!added, "a stale sheet must not take the composer down")
    board.remove(UUID(), from: UUID())
    board.move(UUID(), to: TagPoint(x: 0, y: 0))
    #expect(board.spots.isEmpty)
}

@Test func aBoardLoadedWithAVariantTaggedTwiceComesOutObeyingTheOnePlaceRule() {
    let twice = product("tagged twice by some future writer", foundation)
    let board = LookTagBoard([
        LookTagSpot(photoID: photoOne, point: TagPoint(x: 0.2, y: 0.2), products: [twice]),
        LookTagSpot(photoID: photoTwo, point: TagPoint(x: 0.8, y: 0.8), products: [twice])
    ])
    #expect(board.taggedProductCount == 1)
    #expect(board.placement(of: twice.variantID)?.photoID == photoTwo, "the last one wins")
    #expect(board.spots.count == 1, "and the emptied spot went with it")
}

// MARK: - the list, ordered by category

@Test func theListGroupsByCategoryAndReadsDownThePhotos() {
    var board = LookTagBoard()
    let onTwo = place(&board, on: photoTwo, at: TagPoint(x: 0.8, y: 0.8))
    let onOne = place(&board, on: photoOne, at: TagPoint(x: 0.2, y: 0.2))
    // Tagged out of reading order on purpose: the list must sort, not agree.
    board.add(product("second blush", blush), to: onTwo)
    board.add(product("second foundation", foundation), to: onTwo)
    board.add(product("first foundation", foundation), to: onOne)
    board.add(product("first blush", blush), to: onOne)

    let groups = board.listing(photoOrder: [photoOne, photoTwo])

    #expect(groups.map(\.category.slug) == ["blush", "foundation"], "groups alphabetical by label")
    #expect(groups[0].entries.map(\.product.label) == ["first blush", "second blush"])
    #expect(groups[1].entries.map(\.product.label) == ["first foundation", "second foundation"])
    #expect(groups[0].entries[1].placement.photoID == photoTwo, "the row knows where to scroll to")
}

@Test func aTagOnAPhotoTheReaderOrderDoesNotKnowSortsLastRatherThanVanishing() {
    var board = LookTagBoard()
    let known = place(&board, on: photoOne, at: TagPoint(x: 0.2, y: 0.2))
    let unknown = place(&board, on: photoTwo, at: TagPoint(x: 0.8, y: 0.8))
    board.add(product("known", blush), to: known)
    board.add(product("orphan", blush), to: unknown)

    let groups = board.listing(photoOrder: [photoOne])

    #expect(groups.count == 1)
    #expect(groups[0].entries.map(\.product.label) == ["known", "orphan"])
}

@Test func theListHeadingCountsThisLooksOwnTagsAndClaimsNothing() {
    var board = LookTagBoard()
    #expect(board.listHeading == "products tagged in this look · 0")
    let spot = place(&board, on: photoOne, at: TagPoint(x: 0.5, y: 0.5))
    board.add(product("a", blush), to: spot)
    board.add(product("b", foundation), to: spot)
    #expect(board.listHeading == "products tagged in this look · 2")
    #expect(board.listing(photoOrder: [photoOne]).count == 2, "two categories, one spot")
}
