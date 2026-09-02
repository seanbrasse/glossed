import DataKit
import DesignSystem
import Shelf
import SwiftUI

/// The payoff's example shelf, drawn with the shelf's own bay view (Sean,
/// Sep 2: *"make it an actual shelf like the one we build in app, with the
/// shelf UI, products, etc. … just popular product examples spanning
/// different categories … only products we have images for"*).
///
/// Lives in the app layer because it crosses two features: the products
/// are `Shelf`'s types and the screen is `Onboarding`'s, and features never
/// import features. The onboarding view takes the bay as a closure, the
/// same way it takes the tour.
///
/// **The picks are chosen, not measured.** Twelve products from brands a
/// stranger recognises — the Sephora and Ulta bestseller lists and the
/// press's "cult favourite" roundups agree on them — checked one by one
/// against the local catalog for a cutout. That is why the eyebrow says
/// "a shelf, for example" and no tile carries a number: nobody in the app
/// ranked these yet, and the screen does not pretend otherwise. When the
/// leaderboard has rows, the honest next step is to draw from it instead.
///
/// A pick the catalog cannot match by brand and name WITH an image is
/// skipped, never substituted — the search is fuzzy enough to hand back a
/// candle for "boy brow", and a wrong product on a first screen costs more
/// than a gap.
struct OnboardingExampleShelf: View {
    let client: GlossedClient
    let imageBase: URL?

    @State private var sections: [ShelfSection] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            if !sections.isEmpty {
                ShelfBayView(sections: sections)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            } else if isLoading {
                // Room for three bays while the catalog answers. Not only
                // for the layout: a stack with nothing in it has no size,
                // and SwiftUI never "appears" a zero-size view, so a
                // `.task` on it never runs — the first cut of this view
                // loaded nothing, silently, for exactly that reason.
                Color.clear.frame(height: Self.reservedHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: Tokens.Motion.med), value: sections)
        .task {
            sections = await Self.load(client: client, imageBase: imageBase)
            isLoading = false
        }
    }

    /// Three bays of the shelf's minimum height.
    private static let reservedHeight: CGFloat = 3 * 87

    /// One row per shelf, three shelves. `name` is matched as a prefix of
    /// the catalog's lowercase name so a shade suffix ("north bondi") does
    /// not break the match while "hair oil" cannot land on "lip oil".
    struct Pick: Sendable {
        let brand: String
        let name: String
    }

    struct Row: Sendable {
        let label: String
        let domain: Domain
        let picks: [Pick]
    }

    nonisolated static let shelves: [Row] = [
        Row(label: "makeup", domain: .makeup, picks: [
            Pick(brand: "ilia", name: "super serum skin tint"),
            Pick(brand: "rare beauty", name: "soft pinch liquid blush"),
            Pick(brand: "kosas", name: "revealer concealer"),
            Pick(brand: "fenty beauty", name: "gloss bomb"),
            Pick(brand: "anastasia beverly hills", name: "brow wiz")
        ]),
        Row(label: "skincare", domain: .skincare, picks: [
            Pick(brand: "laneige", name: "lip sleeping mask"),
            Pick(brand: "glow recipe", name: "watermelon glow niacinamide dew drops"),
            Pick(brand: "rhode", name: "glazing milk"),
            Pick(brand: "summer fridays", name: "jet lag mask"),
            Pick(brand: "beauty of joseon", name: "day dew sunscreen")
        ]),
        Row(label: "hair · scent", domain: .haircare, picks: [
            Pick(brand: "ouai", name: "leave in conditioner"),
            Pick(brand: "ouai", name: "hair oil"),
            Pick(brand: "glossier", name: "glossier you"),
            Pick(brand: "sol de janeiro", name: "cheirosa 62")
        ])
    ]

    /// `search_catalog` is anon-granted, so this works before an account
    /// exists. A failed search skips its pick; a shelf with nothing found
    /// is dropped; a screen with nothing found shows no shelf at all.
    nonisolated(unsafe) static var debugMatched = "-"

    /// `search_catalog` is anon-granted, so this works before an account
    /// exists. The fourteen searches run concurrently and land in shelf
    /// order; a failed or unmatched pick is skipped, a shelf with nothing
    /// found is dropped, and a screen with nothing found shows no shelf.
    nonisolated static func load(client: GlossedClient, imageBase: URL?) async -> [ShelfSection] {
        let catalog = CatalogRepository(client: client)
        let found: [Int: [ShelfItem]] = await withTaskGroup(of: (Int, Int, ShelfItem?).self) { group in
            for (row, shelf) in shelves.enumerated() {
                for (slot, pick) in shelf.picks.enumerated() {
                    group.addTask {
                        let hits = await (try? catalog.search("\(pick.brand) \(pick.name)", limit: 15)) ?? []
                        let hit = hits.first { matches($0, pick) }
                        return (row, slot, hit.map { item($0, imageBase: imageBase) })
                    }
                }
            }
            var slots: [Int: [(Int, ShelfItem)]] = [:]
            for await (row, slot, item) in group {
                if let item {
                    slots[row, default: []].append((slot, item))
                }
            }
            return slots.mapValues { $0.sorted { $0.0 < $1.0 }.map(\.1) }
        }
        return shelves.enumerated().compactMap { row, shelf in
            guard let items = found[row], !items.isEmpty else { return nil }
            return ShelfSection(slug: shelf.label, label: shelf.label, domain: shelf.domain, items: items)
        }
    }

    nonisolated static func matches(_ hit: CatalogHit, _ pick: Pick) -> Bool {
        hit.catalogImageKey != nil
            && hit.brandName.lowercased() == pick.brand
            && hit.name.lowercased().hasPrefix(pick.name)
    }

    private nonisolated static func item(_ hit: CatalogHit, imageBase: URL?) -> ShelfItem {
        let aspect: Double? = if let width = hit.catalogImageWidth, let height = hit.catalogImageHeight, height > 0 {
            Double(width) / Double(height)
        } else {
            nil
        }
        return ShelfItem(
            id: hit.id,
            brand: hit.brandName,
            name: hit.name,
            categorySlug: hit.categorySlug,
            categoryLabel: hit.categorySlug,
            domain: hit.domain,
            packaging: ProductMock.Kind.usual(forCategory: hit.categorySlug),
            // The shelf's composition rule (GLO-83): the key rides the
            // storage base; nil base means the drawn mock, never a broken image.
            catalogImageURL: hit.catalogImageKey.flatMap { key in imageBase?.appending(path: key) },
            catalogImageAspect: aspect
        )
    }
}
