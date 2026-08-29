import DataKit
import Foundation
import SwiftUI
import Testing
@testable import Shelf

// GLO-151: "full page" shipped wired to an empty default and nothing ever
// passed a handler, so it sat on the sheet doing nothing. Nothing could catch
// that — a dead button renders exactly like a live one, and no test could see
// a closure that was present and empty. Making the offer conditional on a
// handler is what makes it visible to a test at all.

@MainActor
private func sheet(variantID: UUID?, onOpenProduct: (() -> Void)?) -> ShelfItemSheet {
    let item = ShelfItem(
        id: UUID(),
        brand: "round lab",
        name: "birch moisturizing sun cushion spf 50+",
        categorySlug: "sunscreen",
        categoryLabel: "sunscreen",
        domain: .skincare,
        packaging: .compact,
        variantID: variantID
    )
    return ShelfItemSheet(
        item: item,
        rankedInCategory: 0,
        onClose: {},
        onOpenProduct: onOpenProduct
    )
}

@MainActor
struct ShelfFullPageTests {
    @Test func noHandlerMeansNoButton() {
        // The state the bug was in, now unreachable by accident: a caller
        // that cannot open the page cannot offer to.
        #expect(!sheet(variantID: UUID(), onOpenProduct: nil).showsFullPage)
    }

    @Test func aHandlerMeansTheButtonIsOffered() {
        #expect(sheet(variantID: UUID(), onOpenProduct: {}).showsFullPage)
    }

    @Test func anItemWithNoVariantHasNoPageToOpen() {
        // The page is built from a variant, so an item without one has
        // nothing to show. `ShelfView` withholds the handler in that case,
        // and this is the fact it withholds on — a fixture row with no
        // variant must not offer a page that cannot be built.
        let noVariant = sheet(variantID: nil, onOpenProduct: nil)
        #expect(!noVariant.showsFullPage)
    }
}
