import DataKit
import Foundation
import Testing
@testable import Shelf

// GLO-149: the category label sat in the same band the items stand in, so a
// `large` item — 78pt drawn in an 82pt bay — covered its own label by about
// 16pt, every time. Sean's call: the words go above the images, and the
// images are capped so they cannot reach them. The cap is the load-bearing
// half; without these it is a number that drifts and a shelf that silently
// goes back to being wrong.

@Test func noSizeClassCanReachTheLabelBand() {
    for sizeClass in [ShelfSizeClass.small, .medium, .large] {
        #expect(
            sizeClass.height <= ShelfBayView.itemHeightCap,
            "\(sizeClass) draws \(sizeClass.height), over the \(ShelfBayView.itemHeightCap) cap"
        )
    }
}

@Test func theCapIsWhatTheBayHasLeftOverAfterTheLabel() {
    // The number is derived, not chosen: bay height minus the label's band
    // minus the footing the items stand on. Pinning it here means a change to
    // any of the three has to be a deliberate change to this line too.
    #expect(ShelfBayView.itemHeightCap == 66)
}

@Test func theTallestClassUsesTheCapRatherThanLeavingItOnTheTable() {
    // A cap nothing reaches would mean the shelf gave up height for nothing.
    #expect(ShelfSizeClass.large.height == ShelfBayView.itemHeightCap)
}

@Test func theThreeClassesStayVisiblyDistinctAfterTheCap() {
    // The buckets were scaled, not clamped — clamping would have collapsed
    // medium and large into the same drawn height and lost a size class.
    #expect(ShelfSizeClass.small.height < ShelfSizeClass.medium.height)
    #expect(ShelfSizeClass.medium.height < ShelfSizeClass.large.height)
    #expect(ShelfSizeClass.large.height > ShelfSizeClass.small.height * 1.5)
}

@Test func theSmallestClassStaysClearOfTheSlotFloor() {
    // The constraint that nearly went unnoticed: a compact's slot is its
    // drawn width, and once `height × 0.8` sinks under `minimumSlot` it packs
    // identically to a tube — the shelf keeps three size classes in the type
    // system and shows two. Caught by an existing test on the first attempt
    // at this cap; pinned here so the next change to `height` meets it head-on.
    let compactWidth = ShelfSizeClass.small.height * 0.8
    #expect(compactWidth > ShelfBay.minimumSlot)
    // And clear of it by enough to still pack fewer per bay than a tube does,
    // which is the sharper threshold and the one that actually failed: nine
    // compacts must not fit the 370pt bay the packing test uses.
    #expect(9 * compactWidth + 8 * ShelfBay.itemGap > 370)
}
