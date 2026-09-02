import AddLadder
import DataKit
import DesignSystem
import SwiftUI

// The add-ladder's presentation, extracted for the reason `AppShellDrawer`
// and `AppShellDiscover` were: `AppShell.swift` sits at SwiftLint's 300-line
// ceiling, and the house remedy is to lift a computed projection out rather
// than accrete.
//
// It crossed the line at **301** — one line — when two PRs that each passed
// the gate on their own were squashed onto main within minutes of each other.
// Neither was wrong; the ceiling is measured per file, not per diff, so a
// limit can be broken by a merge rather than by a commit. `main` had no CI
// run of its own to catch it, so the next unrelated PR inherited the failure.

extension AppShell {
    @ViewBuilder var ladderFlow: some View {
        if let client = session.client {
            LadderFlowView(
                catalog: CatalogRepository(client: client),
                shelf: ShelfRepository(client: client),
                tracker: session.tracker,
                // GLO-93: a scanned miss asks the catalog-fill function
                // before the ladder falls through. The function itself
                // fails closed (no key, exhausted budget, unreachable all
                // answer "nothing to add"), so wiring it is unconditional.
                fill: BarcodeFillService(client: client),
                // Before a letter is typed: the discover feed's picks, each
                // with its basis and n (GLO-108, Sean's "suggestions for the
                // user to click on without searching").
                suggestions: AggregatesRepository(client: client),
                query: ladderSeed,
                onClose: {
                    ladderOpen = false
                    ladderSeed = ""
                },
                onShelfChanged: { session.refreshShelf() },
                onLogged: { pendingLog = $0 }
            )
            // Search rows and the variant sheet compose real cutout URLs
            // from this — the same base the shelf reads with (GLO-83).
            .environment(\.catalogImageBase, session.imageBase)
            // One trip per presentation — see `ladderTrip`.
            .id(ladderTrip)
        }
    }
}
