import DesignSystem
import Foundation
import Testing
@testable import AddLadder

// GLO-88: a 40-shade foundation grew the variant sheet past the screen and
// took the header, the close and the confirm with it — a pick you could start
// and never finish. It sat that way for hours because the state was never
// driven, and it was fixed with a row limit and a capped viewport.
//
// Those two constants then guarded the fix with nothing asserting them
// (GLO-168). A shape described only in a comment is one edit away from gone.

@Test func sixShadesSitInlineAndSevenStartScrolling() {
    // The boundary itself. Off by one here and either a compact sheet gains a
    // pointless scroll view, or a seven-row list goes back to growing.
    #expect(!VariantPickSheet.scrolls(variantCount: 6))
    #expect(VariantPickSheet.scrolls(variantCount: 7))
}

@Test func anEmptyOrSingleListNeverScrolls() {
    #expect(!VariantPickSheet.scrolls(variantCount: 0))
    #expect(!VariantPickSheet.scrolls(variantCount: 1))
}

@Test func theSheetStopsGrowingWithTheListPastTheLimit() {
    // The actual GLO-88 guarantee, and the reason the boolean above matters:
    // beyond the limit the viewport is a constant, so the sheet's height no
    // longer depends on how many shades exist. Forty behaves as seven does.
    for count in [7, 14, 40, 200] {
        #expect(VariantPickSheet.scrolls(variantCount: count))
    }
    // The cap is a single value, not a function of the count — stated here
    // because a future change to a per-count height would pass every
    // assertion above and reintroduce the bug.
    #expect(VariantPickSheet.scrollViewportHeight > 0)
}

@Test func theViewportEndsOnAHalfRowSoItReadsAsScrollable() {
    // The cut row is the scroll affordance. A viewport that ended on a whole
    // row would look like the whole list, which is how someone concludes
    // their shade is not there.
    let whole = 6 * Tokens.hitTarget + 5 * Tokens.Space.s2
    #expect(VariantPickSheet.scrollViewportHeight < whole)

    let five = 5 * Tokens.hitTarget + 4 * Tokens.Space.s2
    #expect(VariantPickSheet.scrollViewportHeight > five, "it must show more than five whole rows")
}
