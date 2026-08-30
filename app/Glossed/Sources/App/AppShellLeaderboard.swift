import DataKit
import Leaderboard
import SwiftUI

// GLO-20's last crossing, in its own file for AppShellProductPage's reason:
// `AppShell` sits at SwiftLint's 300-line ceiling, and the house remedy is
// extracting the computed projections.

/// What the product page's "leaderboard" button carries up: enough to open
/// the board scoped to where the tap happened. Both doors hold a slug and a
/// domain (`ShelfItem`, `CatalogHit`) — the model resolves the id itself.
struct BoardContext: Identifiable {
    let categorySlug: String
    let domain: Domain

    var id: String {
        domain.rawValue + "/" + categorySlug
    }
}

extension AppShell {
    /// `G.Leaderboard` as a sheet over the product page — the button was a
    /// dead closure from GLO-151 until this. Row tap-through to a product
    /// page is deliberately not wired yet: from a sheet over a cover it
    /// cannot present correctly in every context, and a tap that half-works
    /// would be worse than none (the "rank it" precedent). Rows render
    /// untappable, which is the view's own rule for an unwired opener.
    @ViewBuilder func leaderboardSheet(_ board: BoardContext) -> some View {
        if let client = session.client {
            LeaderboardView(
                model: LeaderboardModel(
                    store: .repository(
                        aggregates: AggregatesRepository(client: client),
                        catalog: CatalogRepository(client: client)
                    ),
                    categorySlug: board.categorySlug,
                    domain: board.domain,
                    imageBase: session.imageBase
                ),
                onBack: { openBoard = nil }
            )
        }
    }
}
