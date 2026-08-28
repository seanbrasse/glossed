import DataKit
import DesignSystem
import Foundation
import Testing
@testable import Shelf

private func item(_ name: String, packaging: ProductMock.Kind = .bottle, heightMM: Double? = nil) -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: "rare beauty",
        name: name,
        categorySlug: "blush",
        categoryLabel: "blush",
        domain: .makeup,
        packaging: packaging,
        heightMM: heightMM
    )
}

private func section(_ slug: String, _ label: String, count: Int) -> ShelfSection {
    ShelfSection(
        slug: slug, label: label, domain: .makeup,
        items: (0 ..< count).map { item("\(slug) \($0)") }
    )
}

// MARK: - Bays

@Test func aBayHoldsFiveAndTheSixthStartsANewOne() {
    let bays = ShelfBay.bays(from: [section("blush", "blush", count: 6)])
    #expect(bays.count == 2)
    #expect(bays[0].items.count == 5)
    #expect(bays[1].items.count == 1)
}

@Test func theOverflowBayIsNumberedAndTheFirstIsNot() {
    // "blush" then "blush · 2" — a bare repeat of the label reads as two
    // different categories that happen to share a name.
    let bays = ShelfBay.bays(from: [section("blush", "blush", count: 11)])
    #expect(bays.map(\.label) == ["blush", "blush · 2", "blush · 3"])
}

@Test func exactlyFiveItemsIsOneBayWithNoPartNumber() {
    // The off-by-one that would show a lonely "· 2" under an empty ground line.
    let bays = ShelfBay.bays(from: [section("blush", "blush", count: 5)])
    #expect(bays.count == 1)
    #expect(bays[0].label == "blush")
}

@Test func anEmptyCategoryGetsNoGroundLineAtAll() {
    // An empty bay labelled "blush" is a shelf claiming you own blushes.
    #expect(ShelfBay.bays(from: [section("blush", "blush", count: 0)]).isEmpty)
}

@Test func categoriesKeepTheOrderTheyWereGivenIn() {
    let bays = ShelfBay.bays(from: [
        section("blush", "blush", count: 6),
        section("cleanser", "cleanser", count: 1)
    ])
    #expect(bays.map(\.label) == ["blush", "blush · 2", "cleanser"])
}

@Test func everyBayHasItsOwnIdentityEvenWhenLabelsRepeat() {
    // Two bays of one category share a label; SwiftUI needs them not to share
    // an id, or the second redraws as the first.
    let bays = ShelfBay.bays(from: [section("blush", "blush", count: 11)])
    #expect(Set(bays.map(\.id)).count == bays.count)
}

// MARK: - How tall a thing is drawn

@Test func withNoMeasurementTheKitsOwnHeightsStandIn() {
    #expect(item("x", packaging: .compact).drawnScale == 44)
    #expect(item("x", packaging: .bottle).drawnScale == 74)
}

@Test func aCompactIsDrawnSmallerThanABottleWhichIsThePointOfTheWholeThing() {
    // PRD §08: "a lipstick is visibly smaller than a shampoo bottle."
    let compact = item("powder", packaging: .compact, heightMM: 18)
    let shampoo = item("shampoo", packaging: .bottle, heightMM: 190)
    #expect(compact.drawnScale < shampoo.drawnScale)
    // ...and visibly, not by a point. Half again as tall, or the shelf is flat.
    #expect(shampoo.drawnScale > compact.drawnScale * 1.5)
}

@Test func aMeasurementBeatsTheFallbackEvenWhenItDisagreesWithTheShape() {
    // A travel-size bottle is shorter than a full-size jar, and the drawing
    // should say so rather than deferring to what a bottle usually is.
    let travelBottle = item("travel", packaging: .bottle, heightMM: 40)
    let bigJar = item("tub", packaging: .jar, heightMM: 160)
    #expect(travelBottle.drawnScale < bigJar.drawnScale)
}

@Test func nothingVanishesAndNothingOverflowsTheBay() {
    // A sample vial and a litre pump both have to stand in an 82pt bay.
    for mm in [0.5, 1, 15, 200, 400, 5000] as [Double] {
        let scale = item("x", heightMM: mm).drawnScale
        #expect(scale >= ShelfItem.smallestScale)
        #expect(scale <= ShelfItem.largestScale)
    }
}

@Test func aMeaninglessMeasurementFallsBackRatherThanDrawingNothing() {
    // Zero and negative are bad data, not tiny products.
    #expect(item("x", packaging: .jar, heightMM: 0).drawnScale == 50)
    #expect(item("x", packaging: .jar, heightMM: -3).drawnScale == 50)
}

// MARK: - The uprights

private let uprightWidth: CGFloat = 11
private let uprightInset: CGFloat = 14

@Test func theCentreUprightIsActuallyCentred() {
    // A rail off by half its own width looks almost right in a screenshot and
    // wrong once anything stands next to it.
    let width: CGFloat = 390
    let offsets = ShelfBayView.uprightOffsets(in: width)
    #expect(offsets[1] + uprightWidth / 2 == width / 2)
}

@Test func theOuterUprightsAreInsetEquallyFromBothEdges() {
    let width: CGFloat = 390
    let offsets = ShelfBayView.uprightOffsets(in: width)
    #expect(offsets[0] == uprightInset)
    #expect(width - (offsets[2] + uprightWidth) == uprightInset)
}

@Test func theUprightsStayInOrderOnEveryScreenWidth() {
    for width in [320, 375, 390, 430, 1024] as [CGFloat] {
        let offsets = ShelfBayView.uprightOffsets(in: width)
        #expect(offsets == offsets.sorted())
    }
}
