import DataKit
import DesignSystem
import ProductPage
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
                // The sheet's ONE pop moment, and it was a no-op: `ShelfView`
                // never passed `onRank`, so `ShelfItemSheet` took its
                // defaulted `{}` and the primary action on every item did
                // nothing at all (GLO-240).
                onRank: { rankingItem = $0 },
                // The empty shelf's door (GLO-108): straight into the ladder,
                // seeded with a pick's name when a pick was tapped.
                onAddProduct: { seed in
                    ladderSeed = seed
                    ladderTrip = UUID()
                    ladderOpen = true
                },
                // The item sheet's lower half: the product page's evidence in
                // place, behind "swipe up for more" (GLO-108). No user item
                // id on purpose — the sheet keeps its own fit control.
                productDetails: session.client.map { client in
                    { item in
                        AnyView(ProductDetailsView(model: ProductPageModel(
                            product: ProductPageItem(
                                variantID: item.variantID ?? UUID(),
                                brand: item.brand, name: item.name,
                                categoryLabel: item.categoryLabel, variant: item.variant,
                                isAnchor: item.isAnchorCategory
                            ),
                            aggregates: AggregatesRepository(client: client)
                        )).id(item.id))
                    }
                }
            )
            .id(ObjectIdentifier(model))
        } else {
            Text("the shelf came back empty — pull the stack up and relaunch").meta()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.Ground.milk)
        }
    }
}
