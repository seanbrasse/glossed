import DataKit
import Foundation
import SwiftUI
import Testing
@testable import Shelf

// GLO-145: the sheet asked "did the shade fit?" of items nobody had worn,
// directly above the line promising we only match shades people have
// actually worn — and the answer reached `user_shade_anchor`. The gate is
// GLO-87's tried predicate, and these are the four statuses it decides.

@MainActor
private func sheet(anchor: Bool, row: ItemStatus, live: ItemStatus? = nil) -> ShelfItemSheet {
    let item = ShelfItem(
        id: UUID(),
        brand: "revlon",
        name: "colorstay foundation 110 ivory",
        categorySlug: "foundation",
        categoryLabel: "foundation",
        domain: .makeup,
        packaging: .bottle,
        status: row,
        isAnchorCategory: anchor
    )
    return ShelfItemSheet(
        item: item,
        rankedInCategory: 0,
        fit: .constant([]),
        onClose: {},
        status: live
    )
}

@MainActor
struct ShelfFitGateTests {
    @Test func aNeverWornAnchorItemIsNotAskedAboutFit() {
        // The bug, in one assertion: want_to_try is the one status with no
        // wear behind it, so its shade answer would be evidence of nothing.
        #expect(!sheet(anchor: true, row: .wantToTry).showsFit)
    }

    @Test func everyTriedAnchorStatusStillAsksAboutFit() {
        for status in [ItemStatus.own, .finished, .repurchased] {
            #expect(sheet(anchor: true, row: status).showsFit)
        }
    }

    @Test func aNonAnchorCategoryIsNeverAskedHoweverWorn() {
        // The older gate has to survive the new one: shade is only evidence
        // where a shade is meant to match skin.
        #expect(!sheet(anchor: false, row: .own).showsFit)
    }

    @Test func theOptimisticStatusMovesTheSectionNotTheStoredRow() {
        // `liveStatus`, not `item.status`: tapping the bookmark takes the fit
        // question away immediately, and tapping the check brings it back —
        // waiting on the write would leave the contradiction on screen.
        #expect(!sheet(anchor: true, row: .own, live: .wantToTry).showsFit)
        #expect(sheet(anchor: true, row: .wantToTry, live: .own).showsFit)
    }
}
