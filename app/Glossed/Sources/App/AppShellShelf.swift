import DataKit
import DesignSystem
import Shelf
import SwiftUI

/// The shelf tab's construction, split from `AppShell` for the file ceiling —
/// the same shape as the discover and leaderboard tabs.
extension AppShell {
    @ViewBuilder var shelfTab: some View {
        if let model = session.shelfModel {
            // Recreated when the model is (the ladder landed something):
            // `ShelfView` snapshots the reference at init, so identity is what
            // tells SwiftUI this is a new shelf.
            ShelfView(
                model: model,
                // The cold-start shelf's three picks (GLO-211). Built here
                // rather than inside the feature: a feature cannot import a
                // feature, and the shell already owns the client.
                stageZero: session.client.map { .repository(AggregatesRepository(client: $0)) },
                onOpenProduct: { openProduct = $0 },
                onImport: { drawerOpen = true }
            )
            .id(ObjectIdentifier(model))
        } else {
            Text("the shelf came back empty — pull the stack up and relaunch").meta()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.Ground.milk)
        }
    }
}
