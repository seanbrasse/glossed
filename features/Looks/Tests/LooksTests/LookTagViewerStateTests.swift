import CoreGraphics
import Foundation
import Testing
@testable import Looks

// The viewer's four decisions (GLO-266), asserted without a view.

private let frame = CGSize(width: 300, height: 300)
private let lips = TagCategory(slug: "lipstick", label: "lipstick")
private let base = TagCategory(slug: "foundation", label: "foundation")

private struct Fixture {
    let photoOne = UUID()
    let photoTwo = UUID()
    let onOne = UUID()
    let onTwo = UUID()
    let spotOne: UUID
    let spotTwo: UUID
    let state: LookTagViewerState

    init() {
        var board = LookTagBoard()
        guard
            let first = board.place(on: photoOne, at: TagPoint(x: 0.3, y: 0.3), in: frame),
            let second = board.place(on: photoTwo, at: TagPoint(x: 0.7, y: 0.7), in: frame)
        else {
            fatalError("fixture placement was refused")
        }
        spotOne = first
        spotTwo = second
        board.add(TaggedProduct(variantID: onOne, label: "dior lip glow", category: lips), to: first)
        board.add(TaggedProduct(variantID: onTwo, label: "fenty 330", category: base), to: second)
        state = LookTagViewerState(board: board, photoOrder: [photoOne, photoTwo])
    }
}

@Test func tagsAreHiddenUntilTheToggleAsksForThem() {
    // Sean: "Tags only show in the photo when the user clicks on the tag icon
    // in the bottom left." The photo is the content.
    var state = Fixture().state
    #expect(!state.isRevealingTags)
    #expect(state.visibleSpots.isEmpty, "not one dot before the toggle")

    state.toggleTags()

    #expect(state.isRevealingTags)
    #expect(state.visibleSpots.count == 1, "only this photo's dots")
}

@Test func turningTagsOffClosesTheOverlayTooBecauseAnOverlayIsADotOpened() {
    let fixture = Fixture()
    var state = fixture.state
    state.open(spotID: fixture.spotOne)
    #expect(state.openSpot != nil)

    state.toggleTags()

    #expect(!state.isRevealingTags)
    #expect(state.openSpot == nil)
}

@Test func pagingClosesTheOverlayItLeftBehind() {
    let fixture = Fixture()
    var state = fixture.state
    state.open(spotID: fixture.spotOne)

    state.show(index: 1)

    #expect(state.showingPhotoID == fixture.photoTwo)
    #expect(state.openSpot == nil, "that overlay belonged to the photo you just left")
    #expect(state.isRevealingTags, "the toggle is not undone by paging")
    #expect(state.visibleSpots.map(\.id) == [fixture.spotTwo])
}

@Test func revealingAProductOnAnotherPhotoScrollsThereThenShowsTheTag() {
    // Sean: "clicking a product in the list that is tagged in a different
    // photo than the current will scroll to that photo and then show the tag."
    let fixture = Fixture()
    var state = fixture.state
    #expect(state.showingPhotoID == fixture.photoOne)

    let found = state.reveal(fixture.onTwo)

    #expect(found)
    #expect(state.showingPhotoID == fixture.photoTwo, "scrolled")
    #expect(state.isRevealingTags, "tags turned on, because the dot is the point")
    #expect(state.openSpot?.id == fixture.spotTwo, "and the tag is open")
}

@Test func revealingAProductOnThePhotoYouAreAlreadyOnJustOpensIt() {
    let fixture = Fixture()
    var state = fixture.state
    state.reveal(fixture.onOne)
    #expect(state.showingPhotoID == fixture.photoOne)
    #expect(state.openSpot?.id == fixture.spotOne)
}

@Test func revealingSomethingUntaggedIsANoOpNotATrap() {
    var state = Fixture().state
    let found = state.reveal(UUID())
    #expect(!found, "a stale list row must not take the viewer down")
    #expect(state.openSpot == nil)
    #expect(!state.isRevealingTags)
}

@Test func anOverlayNeverFloatsOverTheWrongPicture() {
    // `openSpot` is scoped to the photo on screen, so even a state forced out
    // of step cannot draw a spot belonging to another photo.
    let fixture = Fixture()
    var state = fixture.state
    state.open(spotID: fixture.spotTwo)
    #expect(state.showingPhotoID == fixture.photoTwo)
    #expect(state.openSpot?.id == fixture.spotTwo)
}

@Test func theListIsOrderedByCategoryAndEveryRowKnowsWhereItLives() {
    let fixture = Fixture()
    let state = fixture.state
    let groups = state.listing

    #expect(groups.map(\.category.slug) == ["foundation", "lipstick"], "alphabetical by label")
    let foundationRow = groups[0].entries[0]
    #expect(foundationRow.placement.photoID == fixture.photoTwo)
    #expect(state.isOnAnotherPhoto(foundationRow.placement), "the eye would take you somewhere")
    #expect(!state.isOnAnotherPhoto(groups[1].entries[0].placement))
}

@Test func aLookWithNoTagsOffersNoToggle() {
    // A control with nothing behind it is not offered.
    let state = LookTagViewerState(board: LookTagBoard(), photoOrder: [UUID()])
    #expect(!state.hasTags)
    #expect(state.visibleSpots.isEmpty)
    #expect(state.listing.isEmpty)
}

@Test func anOutOfRangePageIsRefusedRatherThanCrashing() {
    let fixture = Fixture()
    var state = fixture.state
    state.show(index: 9)
    state.show(index: -1)
    #expect(state.showingPhotoID == fixture.photoOne)
    state.show(photoID: UUID())
    #expect(state.showingPhotoID == fixture.photoOne)
}

@Test func theTaggedCountIsProductsNotCategories() {
    // The collapsed listing's header (Sean, Sept 1: "products tagged in the
    // look should be in an expandable tab"). `listing` groups by category, so
    // counting groups would put "2" on a header opening onto however many
    // products those groups hold. The fixture's two products sit in two
    // different categories, which is precisely the case where group-count and
    // product-count agree by accident — so a third product is added to one of
    // them, and only an entry count survives it.
    var board = LookTagBoard()
    let photo = UUID()
    guard let spot = board.place(on: photo, at: TagPoint(x: 0.5, y: 0.5), in: frame) else {
        fatalError("fixture placement was refused")
    }
    board.add(TaggedProduct(variantID: UUID(), label: "dior lip glow", category: lips), to: spot)
    board.add(TaggedProduct(variantID: UUID(), label: "mac ruby woo", category: lips), to: spot)
    board.add(TaggedProduct(variantID: UUID(), label: "fenty 330", category: base), to: spot)

    let state = LookTagViewerState(board: board, photoOrder: [photo])
    #expect(state.listing.count == 2)
    #expect(state.taggedProductCount == 3)
}

@Test func anUntaggedLookOffersNoListingAtAll() {
    // The header is only drawn behind `hasTags`, and a count of zero would be
    // a control with nothing behind it — the composer's rule.
    let state = LookTagViewerState(board: LookTagBoard(), photoOrder: [UUID()])
    #expect(!state.hasTags)
    #expect(state.taggedProductCount == 0)
}
