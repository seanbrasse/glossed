import Browse
import DataKit
import DesignSystem
import Discover
import ProductPage
import SwiftUI

// GLO-20's tab, in its own file for AppShellProductPage's reason: `AppShell`
// sits at SwiftLint's 300-line ceiling, and the house remedy is extracting
// the computed projections.

extension AppShell {
    /// An unbuilt tab names its ticket. The tab exists because the nav is the
    /// kit's; the screen does not, and pretending otherwise helps nobody.
    /// Here rather than in `AppShell.swift` since #266 took that file to the
    /// 300-line ceiling — the same extraction that created this file.
    func unbuiltTab(_ name: String, ticket: String, line: String) -> some View {
        VStack(spacing: Tokens.Space.s2) {
            Text(name).font(Typography.display(30)).foregroundStyle(Tokens.Ink.primary)
            Text(line).meta()
            Badge("not built yet · \(ticket)", tone: .lilac)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Ground.milk)
    }

    /// A tab whose screen EXISTS but whose data did not arrive.
    ///
    /// **A separate state from `unbuiltTab`, because conflating them told a
    /// direct lie for most of a session.** Discover is built and merged (#314,
    /// #371); with an unsigned build the session could not be read back, the
    /// model stayed nil, and this branch announced `not built yet · GLO-20`
    /// over a screen that worked perfectly. Sean read it as a broken app.
    ///
    /// That is GLO-189 in the direction the handoff says nobody watches: copy
    /// that tells you a built thing is unbuilt is exactly as false as copy that
    /// tells you an unbuilt thing is built — it just fails politely, by hiding
    /// work instead of promising it. It also names a ticket that is not the
    /// problem, which sends the next reader to the wrong place entirely.
    /// `because` is the caller's, not a default, because the two reasons this
    /// fires are genuinely different — a read that failed and a session that
    /// does not exist — and one badge covering both would be the same
    /// conflation in a smaller box.
    func unreadableTab(_ name: String, line: String, because: String) -> some View {
        VStack(spacing: Tokens.Space.s2) {
            Text(name).font(Typography.display(30)).foregroundStyle(Tokens.Ink.primary)
            Text(line).meta()
            Badge(because, tone: .butter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Ground.milk)
    }

    /// The discover screen, with the shelf's identity rule: a rebuilt model
    /// is a new screen, and `.id` is what tells SwiftUI so.
    ///
    /// No tap-through yet — the product page opens from a `ShelfItem`'s
    /// variant, and a discover row names a product; wiring that crossing is
    /// GLO-20's next slice, and a tap that half-works would be worse than
    /// none (the "rank it" precedent).
    @ViewBuilder var discoverTab: some View {
        if let model = session.discoverModel {
            DiscoverView(
                model: model,
                onOpenProduct: { openFromCatalog($0) },
                onOpenTrending: { showTrending = true },
                // `G.Discover`'s `leaderboards →`. The stream names the
                // category — the first claiming pick's — because the board
                // needs one and the frame's link does not carry one; its
                // own pills move from there.
                onOpenLeaderboards: { hit in
                    discoverBoard = BoardContext(
                        categorySlug: hit.categorySlug, domain: hit.domain
                    )
                },
                // The tune card (GLO-18): rendered only for the id the gate
                // armed; anything else stays nil and renders nothing.
                injectedCard: { id in
                    guard id == "tune", let client = session.client else { return nil }
                    return AnyView(TuneCardHost(client: client))
                }
            )
            .id(ObjectIdentifier(model))
            .task { await armTuneCard(model) }
            .sheet(isPresented: $showTrending) {
                if let client = session.client {
                    TrendingView(store: .live(BrowseRepository(client: client)))
                }
            }
            // Built here rather than through `leaderboardSheet`, which
            // closes over `openBoard`: this door has its own state, so it
            // needs its own close.
            .sheet(item: $discoverBoard) { board in
                if let client = session.client {
                    LeaderboardBoardSheet(
                        board: board,
                        client: client,
                        imageBase: session.imageBase,
                        onClose: { discoverBoard = nil }
                    )
                }
            }
            .fullScreenCover(item: $openCatalogPage) { page in
                ProductPageView(
                    model: ProductPageModel(
                        product: page.item,
                        aggregates: aggregatesRepository()
                    ),
                    onBack: { openCatalogPage = nil },
                    onRank: { openCatalogPage = nil },
                    // The second door onto the board (GLO-20) — the hit's
                    // category rides on the page wrapper for exactly this.
                    onLeaderboard: {
                        openBoard = BoardContext(
                            categorySlug: page.categorySlug, domain: page.domain
                        )
                    }
                )
                .sheet(item: $openBoard) { board in
                    leaderboardSheet(board)
                }
            }
            .confirmationDialog(
                "which one?",
                isPresented: .init(
                    get: { catalogVariantChoice != nil },
                    set: {
                        if !$0 {
                            catalogVariantChoice = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let choice = catalogVariantChoice {
                    ForEach(choice.variants, id: \.id) { variant in
                        Button(CatalogPage.label(for: variant) ?? "one of \(choice.variants.count)") {
                            openCatalogPage = CatalogPage.build(
                                choice,
                                variant: variant,
                                imageBase: session.imageBase
                            )
                            catalogVariantChoice = nil
                        }
                    }
                }
            }
        } else {
            // Not `unbuiltTab`: this branch is a failed read, not an unbuilt
            // screen. See `unreadableTab`.
            unreadableTab(
                "discover",
                line: "picked for you, from your anchor",
                because: "built — this data didn't load"
            )
        }
    }

    private func aggregatesRepository() -> AggregatesRepository {
        // discoverTab only renders once the session is ready, so the client
        // exists; the guard is for the compiler, not a reachable state.
        guard let client = session.client else { fatalError("discover rendered before boot") }
        return AggregatesRepository(client: client)
    }

    /// A discover hit becomes a page: one variant opens it directly; several
    /// ask which one, because naming one of three would be worse than asking
    /// (the search-row rule, GLO-63's reasoning at a new door).
    func openFromCatalog(_ hit: CatalogHit) {
        guard let client = session.client else { return }
        let catalog = CatalogRepository(client: client)
        Task { @MainActor in
            guard let choice = await CatalogVariantChoice.resolve(hit, catalog: catalog)
            else { return }
            if choice.variants.count == 1, let only = choice.variants.first {
                openCatalogPage = CatalogPage.build(choice, variant: only, imageBase: session.imageBase)
            } else {
                catalogVariantChoice = choice
            }
        }
    }
}

/// The page wrapper `fullScreenCover(item:)` needs — identity is the variant.
struct CatalogPage: Identifiable {
    let item: ProductPageItem
    /// The hit's category, kept for the leaderboard door — `ProductPageItem`
    /// carries only the human label, and the board needs the slug + domain.
    let categorySlug: String
    let domain: Domain
    var id: UUID {
        item.variantID
    }

    /// "240 · 32ml" from the variant's structured fields — the client-side
    /// sibling of SQL's variant_label(), same precedence.
    static func label(for variant: Variant) -> String? {
        var parts: [String] = []
        if let shade = variant.shadeCode {
            parts.append(shade)
        }
        if let size = variant.sizeML {
            parts.append("\(size.formatted())ml")
        }
        if let strength = variant.strengthPct {
            parts.append("\(strength.formatted())%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func build(_ choice: CatalogVariantChoice, variant: Variant, imageBase: URL?) -> CatalogPage {
        CatalogPage(item: ProductPageItem(
            variantID: variant.id,
            brand: choice.hit.brandName,
            name: choice.hit.name,
            categoryLabel: choice.categoryLabel,
            variant: label(for: variant),
            packaging: ProductMock.Kind.usual(forCategory: choice.hit.categorySlug),
            isAnchor: choice.isAnchor,
            catalogImageURL: choice.hit.catalogImageKey.flatMap { imageBase?.appending(path: $0) }
            // userItemID stays nil: not owned, so the fit control is
            // read-only and the page makes no fake-write offer (GLO-47).
        ), categorySlug: choice.hit.categorySlug, domain: choice.hit.domain)
    }
}

/// A multi-variant hit waiting on "which one?".
struct CatalogVariantChoice {
    let hit: CatalogHit
    let variants: [Variant]
    let isAnchor: Bool
    let categoryLabel: String

    /// The hit → page groundwork every catalog door shares (discover
    /// tap-through, leaderboard rows): fetch the variants, name the
    /// category. Nil when the product has no variants to open.
    static func resolve(_ hit: CatalogHit, catalog: CatalogRepository) async -> CatalogVariantChoice? {
        guard let variants = try? await catalog.variants(productID: hit.id), !variants.isEmpty
        else { return nil }
        let category = try? await catalog.categories(domain: hit.domain)
            .first(where: { $0.slug == hit.categorySlug })
        return CatalogVariantChoice(
            hit: hit,
            variants: variants,
            isAnchor: category?.isAnchor ?? false,
            categoryLabel: category?.label ?? hit.categorySlug
        )
    }
}
