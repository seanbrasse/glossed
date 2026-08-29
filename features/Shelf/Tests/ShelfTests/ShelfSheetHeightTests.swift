import Foundation
import Testing
@testable import Shelf

// GLO-160: the sheet had no height bound. On main it ended exactly on the
// bottom edge of a 16 Pro and did not scroll, so the next section added
// pushed `remove from shelf` off the screen while leaving it rendered and
// hit-testable — GLO-88's failure with a different section falling off.
//
// The clamp is the fix, and the important half of it is what it does NOT do.

@Test func aSheetThatFitsIsLeftExactlyAsItIs() {
    // The no-regression guarantee. Every item whose sheet fits today must lay
    // out identically after this change — the bound only ever removes height
    // that was never on screen anyway.
    #expect(ShelfSheetHeight.resolved(content: 400, available: 810) == 400)
    #expect(ShelfSheetHeight.resolved(content: 809, available: 810) == 809)
    #expect(ShelfSheetHeight.resolved(content: 810, available: 810) == 810)
}

@Test func aSheetThatDoesNotFitIsHeldToTheScreen() {
    // The bug case: content taller than the space gets the space, and the
    // scroll view makes the rest reachable instead of invisible.
    #expect(ShelfSheetHeight.resolved(content: 900, available: 810) == 810)
    #expect(ShelfSheetHeight.resolved(content: 2000, available: 810) == 810)
}

@Test func anUnmeasuredSheetFallsBackToTheSpaceRatherThanToNothing() {
    // The first layout pass has no measurement yet. Zero would flash a sheet
    // of no height before the preference arrives, which reads as the sheet
    // failing to open.
    #expect(ShelfSheetHeight.resolved(content: 0, available: 810) == 810)
}

@Test func noSpaceReportedYetMeansTheContentDecides() {
    // A geometry reader can report zero before it has been laid out. Clamping
    // to zero there would collapse the sheet; deferring to the content keeps
    // it whole until a real number arrives.
    #expect(ShelfSheetHeight.resolved(content: 400, available: 0) == 400)
    #expect(ShelfSheetHeight.resolved(content: 400, available: -20) == 400)
}

@Test func theTopGapKeepsAFullSheetClearOfTheNotch() {
    // A full-height sheet must still read as a sheet in front of the shelf
    // rather than a screen that replaced it — and must not run under the
    // notch, which is where the first attempt at this put the header.
    #expect(ShelfSheetHeight.topGap > 44, "a 16 Pro's status area is ~44pt")
}
