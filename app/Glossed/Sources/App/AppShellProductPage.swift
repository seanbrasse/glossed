import DataKit
import ProductPage
import Ranking
import Shelf
import SwiftUI

// GLO-151's crossing, in its own file because `AppShell` is at SwiftLint's
// 300-line ceiling and stored properties cannot move to an extension — the
// house remedy is to extract the computed projections instead (session 7's
// ShelfShownState scar).

extension AppShell {
    /// Closing the product page re-opens the sheet behind it.
    ///
    /// The two are doors onto one `item_fits` row (GLO-47), and the sheet
    /// holds the copy it read when it opened. Without this, answering on the
    /// page leaves the sheet showing the state from before — a screen
    /// contradicting the database, which is the shape of GLO-145.
    func closeProductPage() {
        openProduct = nil
        if let model = session.shelfModel, let open = model.openItem {
            model.open(open)
        }
    }

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
                        catalogImageURL: item.catalogImageURL,
                        // The shelf row's id IS the `user_item_id`, which is
                        // the piece the page's fit control was missing
                        // (GLO-47). Opened from anywhere else it stays nil and
                        // the control does not pretend to save.
                        userItemID: item.id
                    ),
                    aggregates: AggregatesRepository(client: client),
                    fitStore: .repository(ShelfRepository(client: client))
                ),
                onBack: dismiss,
                // Was `dismiss`, which closed the page and opened nothing —
                // the face-off's only entrance, wired to its own exit.
                onRank: { rankingItem = item },
                // GLO-20's last surface: the board opens scoped to this
                // item's category — the shelf row carries the slug + domain.
                onLeaderboard: {
                    openBoard = BoardContext(categorySlug: item.categorySlug, domain: item.domain)
                }
            )
            .sheet(item: $openBoard) { board in
                leaderboardSheet(board)
            }
        }
    }

    /// The face-off, hosted for BOTH of its entrances (GLO-240).
    ///
    /// **Every `rank it` in the app led nowhere.** `ProductPageView`'s was
    /// wired to `dismiss` at all three call sites — the screen's only entrance
    /// pointed at its own exit — and `ShelfItemSheet`'s took `ShelfView`'s
    /// defaulted `{}`, because the passthrough was never added. `Ranking` was
    /// linked into this target and imported by nothing at all. #375 built the
    /// seam and #381 the host screen, both entirely inside the package; the
    /// handoff recorded the face-off as "reachable for the first time since
    /// GLO-17" and it was not reachable at all.
    ///
    /// Presented from the shell rather than from either caller, so the two
    /// entrances feed one presentation instead of racing — the trap the
    /// `openBoard` / `discoverBoard` split already documents.
    ///
    /// A cover, not a sheet: `G.FaceOff` is a whole screen with its own exit,
    /// and a half-height sheet puts the two contenders under the fold at
    /// 402pt.
    @ViewBuilder func faceOff(_ item: ShelfItem) -> some View {
        if let client = session.client {
            RankItView(
                model: RankSessionModel(
                    userItemID: item.id,
                    store: .repository(
                        shelf: ShelfRepository(client: client),
                        catalog: CatalogRepository(client: client),
                        ranking: RankingRepository(client: client)
                    )
                ),
                imageBase: session.imageBase,
                // The face-off writes `rank_positions` and the shelf row
                // carries `rank_position`, so the shelf is stale the moment
                // this closes unless it is told.
                onDone: {
                    rankingItem = nil
                    session.refreshShelf()
                }
            )
        }
    }
}
