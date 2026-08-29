import DataKit
import ProductPage
import Shelf
import SwiftUI

// GLO-151's crossing, in its own file because `AppShell` is at SwiftLint's
// 300-line ceiling and stored properties cannot move to an extension — the
// house remedy is to extract the computed projections instead (session 7's
// ShelfShownState scar).

extension AppShell {
    /// `G.Product` for a shelf item (GLO-151). Everything the page needs is
    /// already on the row — the shelf carries `variantID`, and `ShelfView`
    /// only offers the button when it is there, so the `if` below can only
    /// fail if that gate is ever removed.
    ///
    /// Takes its client and its dismissal rather than reaching for
    /// `AppShell`'s own state: an extension in another file cannot see
    /// `private` members, and widening the shell's state to satisfy a helper
    /// would be the wrong way round.
    ///
    /// "rank it" is deliberately a dismissal for now: the page's own rank
    /// action belongs to the ranking flow (GLO-47), and wiring it to
    /// something that half-works would repeat the defect this ticket fixes.
    @ViewBuilder func productPage(
        for item: ShelfItem,
        rankedInCategory: Int?,
        client: GlossedClient,
        dismiss: @escaping () -> Void
    ) -> some View {
        if let variantID = item.variantID {
            ProductPageView(
                model: ProductPageModel(
                    product: ProductPageItem(
                        variantID: variantID,
                        brand: item.brand,
                        name: item.name,
                        categoryLabel: item.categoryLabel,
                        variant: item.variant,
                        benefitLine: item.benefitLine,
                        packaging: item.packaging,
                        isAnchor: item.isAnchorCategory,
                        rank: item.rank,
                        // The same number the sheet shows. Both halves of
                        // "#1 of 1" must come from one place or a page says
                        // you are first of one while the shelf says
                        // otherwise — the scar tech/01 already carries.
                        rankedInCategory: rankedInCategory,
                        // The same URL the shelf drew from, so one tap does
                        // not change what the product looks like (GLO-153).
                        catalogImageURL: item.catalogImageURL
                    ),
                    aggregates: AggregatesRepository(client: client)
                ),
                onBack: dismiss,
                onRank: dismiss
            )
        }
    }
}
