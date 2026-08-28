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

/// A bottle at its fallback scale, which is what `item()` builds.
private let bottleSlot = item("x").slotWidth

/// Exactly enough shelf for `n` of them, and not a point more.
private func shelfFitting(_ count: Int) -> CGFloat {
    CGFloat(count) * bottleSlot + CGFloat(count - 1) * ShelfBay.itemGap
}

@Test func aBayFillsTheShelfBeforeItOverflows() {
    // The bug this replaced: a fixed capacity of five ended every bay at
    // roughly half the width of the phone (GLO-68).
    let items = (0 ..< 9).map { item("p\($0)") }
    let bays = ShelfBay.chunks(of: items, fittingWidth: shelfFitting(9))
    #expect(bays.count == 1)
    #expect(bays[0].count == 9)
}

@Test func theItemThatWillNotFitStartsTheNextBay() {
    let items = (0 ..< 9).map { item("p\($0)") }
    let bays = ShelfBay.chunks(of: items, fittingWidth: shelfFitting(4))
    #expect(bays.map(\.count) == [4, 4, 1])
}

@Test func oneMorePointOfShelfIsNotOneMoreItem() {
    // Off-by-one at the boundary: a shelf a hair wider than four items must
    // still hold four, because the fifth needs its gap as well as its width.
    let items = (0 ..< 5).map { item("p\($0)") }
    #expect(ShelfBay.chunks(of: items, fittingWidth: shelfFitting(4)).map(\.count) == [4, 1])
    #expect(ShelfBay.chunks(of: items, fittingWidth: shelfFitting(4) + 1).map(\.count) == [4, 1])
    #expect(ShelfBay.chunks(of: items, fittingWidth: shelfFitting(5)).map(\.count) == [5])
}

@Test func aWideItemTakesMoreShelfThanANarrowOne() {
    // The whole point of measuring rather than counting: a bay of compacts
    // holds fewer than a bay of tubes.
    let compacts = (0 ..< 12).map { item("c\($0)", packaging: .compact) }
    let tubes = (0 ..< 12).map { item("t\($0)", packaging: .tube) }
    let width: CGFloat = 370
    let compactsPerBay = ShelfBay.chunks(of: compacts, fittingWidth: width)[0].count
    let tubesPerBay = ShelfBay.chunks(of: tubes, fittingWidth: width)[0].count
    #expect(compactsPerBay < tubesPerBay)
}

@Test func aBayIsPackedByRunningTotalNotByADivision() {
    // A mixed bay has no single item width. Two compacts and a tube fit where
    // three compacts do not, and dividing by any one of them gets it wrong.
    let mixed = [item("a", packaging: .compact), item("b", packaging: .compact), item("c", packaging: .tube)]
    let width = mixed.reduce(0) { $0 + $1.slotWidth } + 2 * ShelfBay.itemGap
    #expect(ShelfBay.chunks(of: mixed, fittingWidth: width).map(\.count) == [3])
    #expect(ShelfBay.chunks(of: mixed, fittingWidth: width - 1).map(\.count) == [2, 1])
}

@Test func anObjectTooBigForItsShelfStillStandsOnIt() {
    // Hanging over the edge is right; dropping it off the screen is not.
    let items = [item("huge"), item("also huge")]
    #expect(ShelfBay.chunks(of: items, fittingWidth: 1).map(\.count) == [1, 1])
}

@Test func aNarrowObjectStillGetsEnoughShelfForItsRankSticker() {
    // A tube draws 17pt wide and its "#10" sticker is nearer 24. Packed on the
    // drawing alone, two tubes would put their stickers on top of each other.
    let tube = item("t", packaging: .tube)
    #expect(ProductMock.drawnWidth(kind: .tube, scale: tube.drawnScale) < ShelfBay.minimumSlot)
    #expect(tube.slotWidth == ShelfBay.minimumSlot)
}

@Test func theOverflowBayIsNumberedAndTheFirstIsNot() {
    // "blush" then "blush · 2" — a bare repeat of the label reads as two
    // different categories that happen to share a name.
    let bays = ShelfBay.bays(from: [section("blush", "blush", count: 9)], fittingWidth: shelfFitting(4))
    #expect(bays.map(\.label) == ["blush", "blush · 2", "blush · 3"])
}

@Test func aCategoryThatFitsOnOneShelfIsNotNumbered() {
    // The off-by-one that would show a lonely "· 2" under an empty ground line.
    let bays = ShelfBay.bays(from: [section("blush", "blush", count: 4)], fittingWidth: shelfFitting(4))
    #expect(bays.count == 1)
    #expect(bays[0].label == "blush")
}

@Test func anEmptyCategoryGetsNoGroundLineAtAll() {
    // An empty bay labelled "blush" is a shelf claiming you own blushes.
    #expect(ShelfBay.bays(from: [section("blush", "blush", count: 0)], fittingWidth: 370).isEmpty)
}

@Test func categoriesKeepTheOrderTheyWereGivenIn() {
    let bays = ShelfBay.bays(
        from: [section("blush", "blush", count: 6), section("cleanser", "cleanser", count: 1)],
        fittingWidth: shelfFitting(4)
    )
    #expect(bays.map(\.label) == ["blush", "blush · 2", "cleanser"])
}

@Test func everyBayHasItsOwnIdentityEvenWhenLabelsRepeat() {
    // Two bays of one category share a label; SwiftUI needs them not to share
    // an id, or the second redraws as the first.
    let bays = ShelfBay.bays(from: [section("blush", "blush", count: 9)], fittingWidth: shelfFitting(4))
    #expect(Set(bays.map(\.id)).count == bays.count)
}

// MARK: - How tall a thing is drawn

@Test func withNoMeasurementTheKindsOwnBucketStandsIn() {
    // GLO-82: a compact is small and a bottle is large, and each draws at
    // its bucket's one height.
    #expect(item("x", packaging: .compact).drawnScale == ShelfSizeClass.small.height)
    #expect(item("x", packaging: .bottle).drawnScale == ShelfSizeClass.large.height)
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
    // A sample vial and a litre pump both have to stand in an 82pt bay —
    // and land in one of the three buckets (GLO-82), never off the scale.
    for mm in [0.5, 1, 15, 200, 400, 5000] as [Double] {
        let scale = item("x", heightMM: mm).drawnScale
        #expect(scale >= ShelfSizeClass.small.height)
        #expect(scale <= ShelfSizeClass.large.height)
    }
}

@Test func aMeaninglessMeasurementFallsBackRatherThanDrawingNothing() {
    // Zero and negative are bad data, not tiny products: the kind's own
    // bucket answers, and a jar is small.
    #expect(item("x", packaging: .jar, heightMM: 0).drawnScale == ShelfSizeClass.small.height)
    #expect(item("x", packaging: .jar, heightMM: -3).drawnScale == ShelfSizeClass.small.height)
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
