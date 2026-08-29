import DataKit
import DesignSystem
import Foundation
import Testing
@testable import Shelf

// GLO-100 (Sean's sketch): want-to-try is an intention, not a bottle — off
// the shelf by default, ghosted in when asked for, and always findable by
// search. These pin the model's half; the opacity is the views'.

private func item(_ name: String, status: ItemStatus = .own) -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: "rare beauty",
        name: name,
        categorySlug: "blush",
        categoryLabel: "blush",
        domain: .makeup,
        packaging: .dropper,
        status: status
    )
}

@MainActor
private func model(_ items: [ShelfItem]) -> ShelfModel {
    ShelfModel(
        sections: [ShelfSection(slug: "blush", label: "blush", domain: .makeup, items: items)],
        selectedDomains: [.makeup]
    )
}

@MainActor
struct ShelfWishlistTests {
    @Test func wantToTryIsOffTheShelfByDefault() {
        let live = model([item("owned"), item("wished", status: .wantToTry)])
        #expect(live.shownSections.flatMap(\.items).map(\.name) == ["owned"])
        #expect(live.shownItemCount == 1, "the count may not include ghosts it is not showing")
    }

    @Test func togglingTheWishlistInShowsThem() {
        let live = model([item("owned"), item("wished", status: .wantToTry)])
        live.showsWishlist = true
        #expect(live.shownSections.flatMap(\.items).count == 2)
        #expect(live.shownItemCount == 2)
    }

    @Test func anAllWishlistCategoryDropsOutWhole() {
        // The empty-bay rule (GLO-73) holds for hidden wishlists too — a bay
        // of nothing-but-ghosts would read as an empty shelf.
        let live = model([item("wished", status: .wantToTry)])
        #expect(live.shownSections.isEmpty)
    }

    @Test func searchFindsAHiddenWish() {
        // "Where did I put that thing I meant to try" is a search, not a
        // browse — an active query overrides the hide.
        let live = model([item("owned"), item("wished", status: .wantToTry)])
        live.searchQuery = "wished"
        #expect(live.shownSections.flatMap(\.items).map(\.name) == ["wished"])
    }

    @Test func clearingTheSearchHidesThemAgain() {
        let live = model([item("owned"), item("wished", status: .wantToTry)])
        live.searchQuery = "wished"
        live.searchQuery = ""
        #expect(live.shownSections.flatMap(\.items).map(\.name) == ["owned"])
    }
}
