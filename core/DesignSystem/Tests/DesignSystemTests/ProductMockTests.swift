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
