import DesignSystem
import Testing
@testable import AddLadder

@Test func everySeededCategoryDrawsAsSomethingItIsSoldIn() {
    // The seven slugs `supabase/seed.sql` creates. A mapping that quietly stops
    // covering the catalog degrades into "everything is a tube", which reads as
    // a rendering bug rather than as the missing-data problem it is.
    #expect(LadderOptionRow.packaging(for: "blush") == .dropper)
    #expect(LadderOptionRow.packaging(for: "serum") == .dropper)
    #expect(LadderOptionRow.packaging(for: "foundation") == .bottle)
    #expect(LadderOptionRow.packaging(for: "cleanser") == .bottle)
    #expect(LadderOptionRow.packaging(for: "styler") == .bottle)
    #expect(LadderOptionRow.packaging(for: "moisturizer") == .jar)
    #expect(LadderOptionRow.packaging(for: "fragrance") == .mist)
}

@Test func acategoryWeHaveNeverSeenGetsTheGenericShape() {
    // The kit's own fallthrough. A category added to the tree tomorrow draws as
    // a tube rather than as a confident wrong silhouette, and nothing crashes.
    for unknown in ["", "concealer", "lip-oil", "🙂", "BLUSH"] {
        #expect(LadderOptionRow.packaging(for: unknown) == .tube)
    }
}

@Test func theMappingIsCaseSensitiveOnPurpose() {
    // `categories.slug` is lowercase by convention. Case-folding here would
    // hide a slug that arrives in the wrong case instead of surfacing it as a
    // generic tube, and the wrong case is a data bug worth seeing.
    #expect(LadderOptionRow.packaging(for: "Blush") == .tube)
}

@Test func theTwoRowsAreTheSameCardAtDifferentTints() {
    // The screen map's caption: "'none of these' carries the same weight as a
    // match at every rung." Same weight is geometry — one set of numbers, used
    // by both rows — and the difference is the fill. If a second radius or a
    // second padding ever appears, the rows have stopped being peers.
    #expect(LadderCard.radius == 16)
    #expect(LadderCard.paddingVertical == 12)
    #expect(LadderCard.paddingHorizontal == 13)
    #expect(LadderCard.gap == 12)
    #expect(LadderCard.thumbWidth == 46)
    #expect(LadderCard.thumbHeight == 50)
    #expect(LadderCard.mockScale == 50)
}
