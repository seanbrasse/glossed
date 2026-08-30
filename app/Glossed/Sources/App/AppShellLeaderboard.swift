import DataKit
import Leaderboard
import ProductPage
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
    /// dead closure from GLO-151 until this.
    @ViewBuilder func leaderboardSheet(_ board: BoardContext) -> some View {
        if let client = session.client {
            LeaderboardBoardSheet(
                board: board,
                client: client,
                imageBase: session.imageBase,
                onClose: { openBoard = nil }
            )
        }
    }
}

/// The board plus its own way onward: a row pushes that product's page
/// inside the sheet's stack. Pushing rather than juggling the covers
/// underneath keeps the crossing self-contained — every context the sheet
/// opens from gets the same working tap, and every push can be left (pop,
/// or dismiss the sheet whole). A page opened here is not owned, so its
/// fit control stays read-only via the nil `userItemID` (GLO-47).
struct LeaderboardBoardSheet: View {
    let board: BoardContext
    let client: GlossedClient
    let imageBase: URL?
    let onClose: () -> Void

    @State private var openPage: CatalogPage?
    @State private var variantChoice: CatalogVariantChoice?

    var body: some View {
        NavigationStack {
            LeaderboardView(
                model: LeaderboardModel(
                    store: .repository(
                        aggregates: AggregatesRepository(client: client),
                        catalog: CatalogRepository(client: client)
                    ),
                    categorySlug: board.categorySlug,
                    domain: board.domain,
                    imageBase: imageBase
                ),
                onBack: onClose,
                onOpenProduct: { open($0) }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openPage) { page in
                ProductPageView(
                    model: ProductPageModel(
                        product: page.item,
                        aggregates: AggregatesRepository(client: client)
                    ),
                    onBack: { openPage = nil },
                    onRank: { openPage = nil },
                    // Already here — the button pops back to the board it
                    // came from rather than sitting dead (the full-page rule).
                    onLeaderboard: { openPage = nil }
                )
                .toolbar(.hidden, for: .navigationBar)
            }
            .confirmationDialog(
                "which one?",
                isPresented: .init(
                    get: { variantChoice != nil },
                    set: {
                        if !$0 {
                            variantChoice = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let choice = variantChoice {
                    ForEach(choice.variants, id: \.id) { variant in
                        Button(CatalogPage.label(for: variant) ?? "one of \(choice.variants.count)") {
                            openPage = CatalogPage.build(choice, variant: variant, imageBase: imageBase)
                            variantChoice = nil
                        }
                    }
                }
            }
        }
    }

    /// The discover door's rule at this one: one variant opens directly,
    /// several ask which, because naming one of three is worse than asking.
    private func open(_ hit: CatalogHit) {
        let catalog = CatalogRepository(client: client)
        Task { @MainActor in
            guard let choice = await CatalogVariantChoice.resolve(hit, catalog: catalog)
            else { return }
            if choice.variants.count == 1, let only = choice.variants.first {
                openPage = CatalogPage.build(choice, variant: only, imageBase: imageBase)
            } else {
                variantChoice = choice
            }
        }
    }
}

/// `navigationDestination(item:)` wants Hashable; the struct's own stated
/// identity is the variant, so equality and hash follow it.
extension CatalogPage: Hashable {
    static func == (lhs: CatalogPage, rhs: CatalogPage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
