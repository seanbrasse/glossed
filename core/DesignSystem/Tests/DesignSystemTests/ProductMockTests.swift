import CoreGraphics
import Testing
@testable import DesignSystem

@Test func everyKitSilhouetteIsPortedAndNoneWereInvented() {
    // `G.Mock` in the kit branches on five names and falls through to a sixth
    // shape for anything else. Drifting from that list is how a shelf ends up
    // drawing a kind the frames never show.
    #expect(Set(ProductMock.Kind.allCases.map(\.rawValue)) == [
        "tube", "bottle", "dropper", "jar", "compact", "mist"
    ])
}

@Test func theKindTheKitFallsThroughToIsTheDefault() {
    // The kit's `else` branch draws a tube, so a caller that knows nothing
    // about the packaging gets the same shape the kit would have drawn.
    #expect(ProductMock.Kind(rawValue: "tube") == .tube)
}

@Test func theSameSeedIsAlwaysTheSameMockTintInEveryProcess() {
    // Pinned values, not self-comparison — the same trap `TypographicTile`
    // documents. `hashValue` is stable within a process, so comparing the rule
    // against itself passes for the very implementation this forbids. Only
    // constants written down here fail when someone reaches for it.
    #expect(ProductMock.tintIndex(for: "blush") == 2)
    #expect(ProductMock.tintIndex(for: "serum") == 1)
    #expect(ProductMock.tintIndex(for: "shampoo") == 4)
    #expect(ProductMock.tintIndex(for: "cleanser") == 0)
    #expect(ProductMock.tintIndex(for: "mascara") == 3)
    #expect(ProductMock.tintIndex(for: "") == 0)
}

@Test func differentSeedsSpreadAcrossTheMockPalette() {
    let seeds = ["blush", "serum", "shampoo", "cleanser", "mascara", "lipstick", "toner", "mask"]
    // Not a distribution proof — just that the tint is not a constant dressed
    // up as a function, which is how this silently degrades.
    #expect(Set(seeds.map(ProductMock.tintIndex(for:))).count > 1)
}

@Test func everySeedLandsInTheMockPalette() {
    for seed in ["", "a", "🙂", "이니스프리", String(repeating: "z", count: 5000)] {
        #expect(ProductMock.tints.indices.contains(ProductMock.tintIndex(for: seed)))
    }
}

@Test func theMockAndTheTileDoNotShareARule() {
    // Two palettes of different sizes. If someone collapses them into one
    // helper the pinned values above stop meaning anything, and a product's
    // tile and its drawn mock start disagreeing about its colour.
    #expect(ProductMock.tints.count != TypographicTile.tints.count)
}

@Test func aRankLabelIsReadAloudAsARankRatherThanAsPunctuation() {
    // "#2" spoken as "hash two" tells a screen-reader user nothing. Every
    // label the shelf sets is a rank, so the `#` becomes the word for it.
    #expect(ProductMock.spoken("#1") == "ranked 1")
    #expect(ProductMock.spoken("#12") == "ranked 12")
    #expect(ProductMock.spoken(" #3 ") == "ranked 3")
}

@Test func aLabelThatIsNotARankIsSpokenAsItself() {
    // The sticker is a general slot; only the shelf's use of it is ranks. A
    // caller that puts something else there must not have it prefixed with a
    // claim about ranking that is not true.
    #expect(ProductMock.spoken("new") == "new")
    #expect(ProductMock.spoken("") == "")
}

/// Points, compared loosely — these are `Double` multiplications and 100 × 0.28
/// is 28.000000000000004. A tenth of a point is far below anything drawable.
private func isNear(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
    abs(lhs - rhs) < 0.1
}

@Test func everyKindReportsTheWidthOfItsWidestPiece() {
    // A jar's lid is narrower than its body and a dropper's cap is much
    // narrower than its bottle, so "how wide is this" is the widest piece —
    // which is what a caller laying two of them side by side needs.
    #expect(isNear(ProductMock.drawnWidth(kind: .compact, scale: 100), 80))
    #expect(isNear(ProductMock.drawnWidth(kind: .jar, scale: 100), 66))
    #expect(isNear(ProductMock.drawnWidth(kind: .bottle, scale: 100), 42))
    #expect(isNear(ProductMock.drawnWidth(kind: .dropper, scale: 100), 36))
    #expect(isNear(ProductMock.drawnWidth(kind: .mist, scale: 100), 32))
    #expect(isNear(ProductMock.drawnWidth(kind: .tube, scale: 100), 28))
}

@Test func widthScalesLinearlyAndNeverGoesNegative() {
    #expect(isNear(ProductMock.drawnWidth(kind: .bottle, scale: 50), 21))
    #expect(ProductMock.drawnWidth(kind: .bottle, scale: 0) == 0)
}

@Test func aCompactIsTheWidestKindAndATubeTheNarrowest() {
    // Not arithmetic for its own sake: the shelf packs bays by width, so which
    // kind is widest decides how many fit, and a silent reordering here would
    // quietly change every bay in the app.
    let widths = ProductMock.Kind.allCases.map { ($0, ProductMock.drawnWidth(kind: $0, scale: 100)) }
    #expect(widths.max { $0.1 < $1.1 }?.0 == .compact)
    #expect(widths.min { $0.1 < $1.1 }?.0 == .tube)
}

@Test func everySeededCategoryDrawsTheShapeTheKitDrew() {
    // The kit's own assignments, one per seeded category. The ladder's rows and
    // the shelf's bays both read this table, so it lives on the primitive.
    #expect(ProductMock.Kind.usual(forCategory: "blush") == .dropper)
    #expect(ProductMock.Kind.usual(forCategory: "serum") == .dropper)
    #expect(ProductMock.Kind.usual(forCategory: "foundation") == .bottle)
    #expect(ProductMock.Kind.usual(forCategory: "cleanser") == .bottle)
    #expect(ProductMock.Kind.usual(forCategory: "styler") == .bottle)
    #expect(ProductMock.Kind.usual(forCategory: "moisturizer") == .jar)
    #expect(ProductMock.Kind.usual(forCategory: "fragrance") == .mist)
}

@Test func anUnknownCategoryGetsTheGenericShapeNotAConfidentWrongOne() {
    #expect(ProductMock.Kind.usual(forCategory: "lip-oil") == .tube)
    #expect(ProductMock.Kind.usual(forCategory: "") == .tube)
}
