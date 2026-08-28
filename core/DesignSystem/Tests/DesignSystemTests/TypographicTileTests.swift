import Testing
@testable import DesignSystem

@Test func oneWordBrandsGetOneLetter() {
    // "GL" would read as an abbreviation of something rather than an initial.
    #expect(TypographicTile.letters(of: "Glossier") == "G")
    #expect(TypographicTile.letters(of: "byoma") == "B")
}

@Test func twoWordBrandsGetTwo() {
    #expect(TypographicTile.letters(of: "Rare Beauty") == "RB")
    #expect(TypographicTile.letters(of: "glow recipe") == "GR")
}

@Test func longBrandsStopAtTwo() {
    #expect(TypographicTile.letters(of: "Paula's Choice Skincare") == "PC")
    #expect(TypographicTile.letters(of: "e.l.f. Cosmetics Beauty Shield") == "EC")
}

@Test func hyphensSeparateWordsBecauseBrandsUseThem() {
    #expect(TypographicTile.letters(of: "Drunk-Elephant") == "DE")
}

@Test func aBrandWithNoLettersStillRendersSomething() {
    // The tile is the floor of the fallback chain. It does not get to fail.
    for unnameable in ["", "   ", "-", "  - "] {
        #expect(TypographicTile.letters(of: unnameable) == "?")
    }
}

@Test func theSameSeedIsAlwaysTheSameColour() {
    // Swift's hashValue is seeded per process, so a hash-based tint would give
    // a product a different colour on every launch — which reads as a bug, and
    // makes a shelf look reshuffled when nothing moved.
    for seed in ["blush", "serum", "shampoo", "lip-oil", ""] {
        #expect(TypographicTile.tintIndex(for: seed) == TypographicTile.tintIndex(for: seed))
    }
}

@Test func differentSeedsSpreadAcrossThePalette() {
    let seeds = ["blush", "serum", "shampoo", "cleanser", "mascara", "lipstick", "toner", "mask"]
    // Not a distribution proof — just that the tint is not a constant dressed
    // up as a function, which is how this silently degrades.
    #expect(Set(seeds.map(TypographicTile.tintIndex(for:))).count > 1)
}

@Test func everySeedLandsInThePalette() {
    // Including the ones that could overflow or divide badly.
    for seed in ["", "a", "🙂", String(repeating: "z", count: 5000)] {
        #expect(TypographicTile.tints.indices.contains(TypographicTile.tintIndex(for: seed)))
    }
}
