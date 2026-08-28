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

@Test func theSameSeedIsAlwaysTheSameColourInEveryProcess() {
    // Pinned values, not self-comparison. `hashValue` is seeded per *process*
    // but stable *within* one, so `tintIndex(x) == tintIndex(x)` passes even
    // for the hash-based implementation this rule exists to avoid. Only
    // constants written down here fail when someone reaches for the shortcut.
    #expect(TypographicTile.tintIndex(for: "blush") == 2)
    #expect(TypographicTile.tintIndex(for: "serum") == 0)
    #expect(TypographicTile.tintIndex(for: "shampoo") == 3)
    #expect(TypographicTile.tintIndex(for: "cleanser") == 1)
    #expect(TypographicTile.tintIndex(for: "lip-oil") == 2)
    #expect(TypographicTile.tintIndex(for: "") == 0)
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

@Test func brandsThatAreNotLatinStillGetTheirOwnInitial() {
    // The floor of the fallback chain has to hold for the whole catalog, not
    // the English-language part of it.
    #expect(TypographicTile.letters(of: "이니스프리") == "이")
    #expect(TypographicTile.letters(of: "資生堂") == "資")
    #expect(TypographicTile.letters(of: "Л'Этуаль") == "Л")
    #expect(TypographicTile.letters(of: "قمر") == "ق")
}
