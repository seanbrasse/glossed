#if DEBUG

    import AddLadder
    import DataKit
    import DesignSystem
    import ProductPage
    import Shelf
    import SwiftUI

    // Fixtures for the debug catalog.
    //
    // Deliberately duplicated from the packages' test doubles rather than
    // shared: an app target cannot import a test target, and moving `FakeCatalog`
    // into a package's product would ship a stub in the release binary. The
    // duplication is small, `#if DEBUG`, and honest about which of the two it is.

    // MARK: - Catalog doubles

    extension GlossedError {
        /// The one failure the catalog needs to show — a lookup that did not
        /// happen, which the search rung must never dress up as an empty
        /// catalog.
        static let offline = GlossedError(.offline, userMessage: "no connection — try again in a sec.")
    }

    actor StubCatalog: CatalogSearching {
        private let hits: [CatalogHit]
        private let failure: GlossedError?

        init(hits: [CatalogHit] = [], failure: GlossedError? = nil) {
            self.hits = hits
            self.failure = failure
        }

        func search(_: String, limit _: Int) async throws(GlossedError) -> [CatalogHit] {
            if let failure {
                throw failure
            }
            return hits
        }

        func recordFailedSearch(_: String, domain _: Domain?) async {}
    }

    actor StubVariants: VariantLookup {
        func variant(gtin _: String) async throws(GlossedError) -> Variant? {
            nil
        }
    }

    /// `CatalogHit` has no public memberwise init — it is a wire model, and its
    /// synthesised one is internal to DataKit. The package tests build one by
    /// decoding, and so does this.
    ///
    /// Optional rather than `try!`: a fixture that fails to decode should thin
    /// the catalog, not take the picker down with it. A missing row is obvious
    /// the moment you open the screen; a crash on launch is a debug tool that
    /// nobody can use to debug anything.
    func stubHit(_ name: String, brand: String, category: String, scope: String = "canonical") -> CatalogHit? {
        let json = """
        {"id":"\(UUID().uuidString)","name":"\(name)","brand_name":"\(brand)",
         "category_slug":"\(category)","domain":"makeup","scope":"\(scope)"}
        """
        return try? JSONDecoder().decode(CatalogHit.self, from: Data(json.utf8))
    }

    // MARK: - Shelf

    enum ShelfFixtures {
        static func item(
            _ brand: String,
            _ name: String,
            variant: String? = nil,
            category: (slug: String, label: String) = ("blush", "blush"),
            domain: Domain = .makeup,
            packaging: ProductMock.Kind = .dropper,
            heightMM: Double? = nil,
            benefit: String? = nil,
            startedDaysAgo: Double? = nil,
            personal: Bool = false,
            rank: Int? = nil
        ) -> ShelfItem {
            ShelfItem(
                id: UUID(),
                brand: brand,
                name: name,
                categorySlug: category.slug,
                categoryLabel: category.label,
                domain: domain,
                variant: variant,
                packaging: packaging,
                heightMM: heightMM,
                benefitLine: benefit,
                status: .own,
                startedOn: startedDaysAgo.map { Date().addingTimeInterval(-$0 * 86400) },
                isPersonalScope: personal,
                rank: rank,
                loggedAt: Date().addingTimeInterval(-Double(rank ?? 9) * 86400)
            )
        }

        /// Five blushes, three cleansers, two stylers, one fragrance.
        ///
        /// Shaped for the things that have actually gone wrong: two products in
        /// one category (so identical drawings are visible), a personal-scope
        /// item, a brand long enough to overflow its sticker, a travel size next
        /// to a full size with real `height_mm`, and something wearing in so the
        /// status line reads "week 3" rather than "own".
        static let sections: [ShelfSection] = [
            ShelfSection(slug: "blush", label: "blush", domain: .makeup, items: [
                item(
                    "rare beauty",
                    "soft pinch liquid blush",
                    variant: "joy · 7.5ml",
                    benefit: "one dot, blends forever. the only blush that survives a full shift on combo skin.",
                    rank: 1
                ),
                item(
                    "rhode",
                    "pocket blush",
                    variant: "freckle",
                    packaging: .compact,
                    benefit: "cream-to-skin finish, dewy without shine. melts a little past 30°C.",
                    rank: 2
                ),
                item("glossier", "cloud paint", variant: "beam", packaging: .tube, rank: 3),
                item("benefit", "baked blush", variant: "luminoso", packaging: .compact, rank: 4),
                item(
                    "the shelf lab",
                    "beetroot cream",
                    variant: "homemade",
                    packaging: .jar,
                    benefit: "yours until three people log it.",
                    personal: true
                )
            ]),
            ShelfSection(slug: "cleanser", label: "cleanser", domain: .skincare, items: [
                item(
                    "rhode",
                    "pineapple refresh",
                    variant: "150ml",
                    category: ("cleanser", "cleanser"),
                    domain: .skincare,
                    packaging: .bottle,
                    heightMM: 150,
                    benefit: "gel-to-foam, no tightness after. week three and no purge.",
                    startedDaysAgo: 15,
                    rank: 1
                ),
                item(
                    "cerave",
                    "hydrating cleanser",
                    variant: "236ml",
                    category: ("cleanser", "cleanser"),
                    domain: .skincare,
                    packaging: .bottle,
                    heightMM: 190,
                    rank: 2
                ),
                item(
                    "byoma",
                    "travel cleanser",
                    variant: "50ml",
                    category: ("cleanser", "cleanser"),
                    domain: .skincare,
                    packaging: .bottle,
                    heightMM: 40,
                    rank: 3
                )
            ]),
            ShelfSection(slug: "styler", label: "stylers", domain: .haircare, items: [
                item(
                    "curlsmith",
                    "flaxseed gel",
                    variant: "237ml",
                    category: ("styler", "stylers"),
                    domain: .haircare,
                    packaging: .bottle,
                    rank: 1
                ),
                item(
                    "ouai",
                    "wave spray",
                    variant: "150ml",
                    category: ("styler", "stylers"),
                    domain: .haircare,
                    packaging: .mist,
                    rank: 2
                )
            ]),
            ShelfSection(slug: "fragrance", label: "fragrance", domain: .fragrance, items: [
                item(
                    "phlur",
                    "missing person",
                    variant: "50ml edp",
                    category: ("fragrance", "fragrance"),
                    domain: .fragrance,
                    packaging: .bottle,
                    heightMM: 90,
                    rank: 1
                )
            ])
        ]

        /// Eleven blushes: three bays, so the `· 2` and `· 3` labels and the
        /// single-item overflow bay are both on screen.
        static let overflowing: [ShelfSection] = [
            ShelfSection(
                slug: "blush", label: "blush", domain: .makeup,
                items: (1 ... 11).map { item("brand \($0)", "blush number \($0)", rank: $0) }
            )
        ]
    }

    // MARK: - AddLadder

    enum LadderFixtures {
        static let hits = [
            stubHit("soft pinch liquid blush", brand: "rare beauty", category: "blush"),
            stubHit("soft pinch luminous blush", brand: "rare beauty", category: "blush"),
            stubHit("flaxseed curl gel", brand: "the shelf lab", category: "styler", scope: "personal")
        ].compactMap(\.self)

        /// Two products in one category, which is the case that made every row
        /// draw as the same pink dropper before the tint was seeded on the name.
        static let nearMatches = [
            stubHit("soft pinch liquid blush", brand: "rare beauty", category: "blush"),
            stubHit("soft pinch tinted moisturizer", brand: "rare beauty", category: "foundation"),
            stubHit("soft pinch liquid blush", brand: "rare beauty", category: "blush")
        ].compactMap(\.self)

        static func ladderAtNearMatches(query: String) -> Ladder {
            var ladder = Ladder(entry: .search, query: query)
            ladder.noneOfThese()
            ladder.noneOfThese()
            return ladder
        }
    }

    // MARK: - ProductPage

    actor StubAggregates: ShadeEvidenceReading {
        private let evidence: PayoffEvidence?
        private let failure: GlossedError?

        init(evidence: PayoffEvidence? = nil, failure: GlossedError? = nil) {
            self.evidence = evidence
            self.failure = failure
        }

        func payoff(variantID _: UUID) async throws(GlossedError) -> PayoffEvidence {
            if let failure {
                throw failure
            }
            return evidence ?? PayoffEvidence(exactShadeCount: 0, withFitCount: 0, evidenceBacked: false)
        }
    }

    enum ProductFixtures {
        /// The kit's own fixture: rhode pocket blush, #2 of 5, 89 reports.
        static let pocketBlush = ProductPageItem(
            variantID: UUID(),
            brand: "rhode",
            name: "pocket blush",
            categoryLabel: "cream blush",
            variant: "freckle",
            benefitLine: "the natural flush",
            packaging: .compact,
            isAnchor: true,
            rank: 2,
            rankedInCategory: 5
        )

        /// Not an anchor, so no fit block and no confidence meter — the shape of
        /// the page for most of the catalog.
        static let notAnAnchor = ProductPageItem(
            variantID: UUID(),
            brand: "glossier",
            name: "cloud paint",
            categoryLabel: "cream blush",
            variant: "beam",
            benefitLine: "gel-cream, buildable to a flush",
            packaging: .tube,
            isAnchor: false,
            rank: 3,
            rankedInCategory: 5
        )
    }
#endif
