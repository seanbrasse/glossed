#if DEBUG

    import AddLadder
    import DataKit
    import DesignSystem
    import Import
    import ProductPage
    import Shelf
    import SwiftUI

    @MainActor
    enum ShelfEntries {
        static let bays = ScreenEntry(
            id: "shelf-bays",
            title: "shelf · bays",
            note: "four domains, real height_mm on the cleansers — a travel bottle stands shorter than a full one"
        ) {
            ShelfView(model: ShelfModel(sections: ShelfFixtures.sections))
        }

        static let baysWithOverflow = ScreenEntry(
            id: "shelf-overflow",
            title: "shelf · a category that overflows",
            note: "eleven blushes across two bays — packing is by width, so the bay count moves when item sizes do"
        ) {
            ShelfView(model: ShelfModel(sections: ShelfFixtures.overflowing, selectedDomains: [.makeup]))
        }

        static let list = ScreenEntry(
            id: "shelf-list",
            title: "shelf · list",
            note: "one category open, the rest collapsed with their counts. 'the shelf lab' is personal scope"
        ) {
            ShelfView(model: ShelfModel(
                sections: ShelfFixtures.sections, viewMode: .list, openSection: "blush"
            ))
        }

        static let sheetOpen = ScreenEntry(
            id: "shelf-sheet",
            title: "shelf · item sheet",
            note: "'week 3' from started_on, and a rank denominator counting only what has been ranked"
        ) {
            SheetOpenOnLaunch()
        }

        static let everythingOff = ScreenEntry(
            id: "shelf-no-domains",
            title: "shelf · every domain off",
            note: "no bays, count reads zero, and nothing crashes — the state a filter can always reach"
        ) {
            ShelfView(model: ShelfModel(sections: ShelfFixtures.sections, selectedDomains: []))
        }

        /// The sheet is model state, so it opens by tapping. Doing that here on
        /// appear means the catalog can offer the sheet as a state of its own
        /// rather than as a thing you have to find first.
        private struct SheetOpenOnLaunch: View {
            @State private var model = ShelfModel(sections: ShelfFixtures.sections)

            var body: some View {
                ShelfView(model: model)
                    .task {
                        if let first = ShelfFixtures.sections.first?.items.first {
                            model.open(first)
                        }
                    }
            }
        }
    }

    @MainActor
    enum LadderEntries {
        static let search = ScreenEntry(
            id: "ladder-search",
            title: "ladder 1 · search",
            note: "three matches, one of them personal scope. the butter escape row is the one to look at"
        ) {
            SearchRungView(model: SearchRungModel(
                catalog: StubCatalog(hits: LadderFixtures.hits), query: "rare beauty soft pin"
            ))
        }

        static let searchEmpty = ScreenEntry(
            id: "ladder-search-empty",
            title: "ladder 1 · nothing found",
            note: "a real query that came back empty — 'we noted that you looked', and the way out is still there"
        ) {
            SearchRungView(model: SearchRungModel(catalog: StubCatalog(), query: "laneige lip mask"))
        }

        static let searchFailed = ScreenEntry(
            id: "ladder-search-failed",
            title: "ladder 1 · the lookup failed",
            note: "must NOT read as an empty catalog: a failure is not evidence that a product does not exist"
        ) {
            SearchRungView(model: SearchRungModel(
                catalog: StubCatalog(failure: .offline), query: "rare beauty"
            ))
        }

        static let barcodeNoCamera = ScreenEntry(
            id: "ladder-barcode-no-camera",
            title: "ladder 2 · a phone that cannot scan",
            note: "#47's bug: the card must not tell someone to point a camera they do not have"
        ) {
            BarcodeRungView(model: BarcodeRungModel(
                catalog: StubVariants(), availability: .unsupportedDevice
            ))
        }

        static let nearMatches = ScreenEntry(
            id: "ladder-near",
            title: "ladder 3 · near matches",
            note: "two products in one category — the case where identical drawings defeat 'check the photo'"
        ) {
            NearMatchRungView(model: NearMatchRungModel(
                catalog: StubNearMatching(matches: NearMatchFixtures.candidates),
                ladder: LadderFixtures.ladderAtNearMatches(query: "rare beauty soft pinch")
            ))
        }

        static let nearMatchesAfterAMissedScan = ScreenEntry(
            id: "ladder-near-no-name",
            title: "ladder 3 · arrived from a missed scan",
            note: "a GTIN and no name, so the rung has to ask for one — the only state with a field on it"
        ) {
            NearMatchRungView(model: NearMatchRungModel(
                catalog: StubNearMatching(matches: NearMatchFixtures.candidates),
                ladder: LadderFixtures.ladderAtNearMatches(query: "")
            ))
        }
    }

    @MainActor
    enum GalleryEntries {
        static let productMock = ScreenEntry(
            id: "ds-product-mock",
            title: "design system · ProductMock",
            note: "every kind at shelf heights on one ground line — a compact is visibly smaller than a bottle"
        ) {
            ProductMockGallery()
        }

        private struct ProductMockGallery: View {
            var body: some View {
                VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                    Text("EVERY KIND · SHELF HEIGHTS · RANK STICKER").eyebrow()
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array(ProductMock.Kind.allCases.enumerated()), id: \.element) { index, kind in
                            ProductMock(
                                kind: kind,
                                tint: ProductMock.tint(for: kind.rawValue),
                                scale: ShelfItem.kitSizeClass(kind).height,
                                rotation: .degrees([-2, 1.5, -1, 2, -1.5][index % 5]),
                                label: "#\(index + 1)"
                            )
                        }
                    }
                    Rectangle()
                        .fill(Tokens.Support.butterSoft)
                        .frame(height: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
                        )
                    Spacer(minLength: 0)
                }
                .padding(Tokens.Space.s5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Tokens.Ground.milk)
            }
        }
    }

    @MainActor
    enum ProductEntries {
        static let backed = ScreenEntry(
            id: "product-backed",
            title: "product · evidence backed",
            note: "89 reports in your shade, #2 of 5, and the meter at 2 of 5 anchors"
        ) {
            ProductPageView(model: ProductPageModel(
                product: ProductFixtures.pocketBlush,
                aggregates: StubAggregates(
                    evidence: PayoffEvidence(exactShadeCount: 89, withFitCount: 2, evidenceBacked: true)
                ),
                fitStore: .picker
            ))
        }

        static let thinSample = ScreenEntry(
            id: "product-thin",
            title: "product · not enough reports yet",
            note: "a promise, not an apology — and the anchor count is still real, because that is about you"
        ) {
            ProductPageView(model: ProductPageModel(
                product: ProductFixtures.pocketBlush,
                aggregates: StubAggregates(
                    evidence: PayoffEvidence(exactShadeCount: 2, withFitCount: 3, evidenceBacked: false)
                ),
                fitStore: .picker
            ))
        }

        static let lookupFailed = ScreenEntry(
            id: "product-failed",
            title: "product · the evidence lookup failed",
            note: "must NOT read as 'not enough reports': we did not ask, so we know nothing"
        ) {
            ProductPageView(model: ProductPageModel(
                product: ProductFixtures.pocketBlush,
                aggregates: StubAggregates(failure: .offline)
            ))
        }

        static let notAnAnchor = ScreenEntry(
            id: "product-no-anchor",
            title: "product · not an anchor category",
            note: "no fit block and no meter — shade is only evidence where a shade is meant to match skin"
        ) {
            ProductPageView(model: ProductPageModel(
                product: ProductFixtures.notAnAnchor,
                aggregates: StubAggregates(
                    evidence: PayoffEvidence(exactShadeCount: 52, withFitCount: 2, evidenceBacked: true)
                ),
                fitStore: .picker
            ))
        }
    }

    @MainActor
    enum ImportEntries {
        static let sourcePick = ScreenEntry(
            id: "import-sources",
            title: "import · pick a source",
            note: "three cards, one tint each — the state before anyone has pasted anything"
        ) {
            ImportView(model: ImportModel(parser: StubImportParser()))
        }

        static let parsed = ScreenEntry(
            id: "import-parsed",
            title: "import · the kit's messy list",
            note: "'3 of 5 matched outright' and 'add 4 to your shelf' on one screen — two counts, on purpose"
        ) {
            ParsedOnLaunch(
                parser: StubImportParser(ImportFixtures.kitOutcome),
                note: nil
            )
        }

        static let nothingMatched = ScreenEntry(
            id: "import-no-matches",
            title: "import · nothing matched",
            note: "five misses is a full ladder handoff, not an error — every row offers 'fix →'"
        ) {
            ParsedOnLaunch(parser: StubImportParser(), note: nil)
        }

        static let parseFailed = ScreenEntry(
            id: "import-parse-failed",
            title: "import · the parse failed",
            note: "must NOT list five misses: a parse that did not happen says nothing about the catalog"
        ) {
            ParsedOnLaunch(parser: StubImportParser(failure: .offline), note: nil)
        }

        /// The parse runs on appear so the catalog can offer its result as a
        /// state rather than as something you have to trigger first.
        private struct ParsedOnLaunch: View {
            let parser: StubImportParser
            let note: String?
            @State private var model: ImportModel?

            var body: some View {
                Group {
                    if let model {
                        ImportView(model: model)
                    } else {
                        Color.clear
                    }
                }
                .task {
                    let fresh = ImportModel(parser: parser, text: ImportFixtures.paste)
                    fresh.source = .notes
                    await fresh.parse()
                    model = fresh
                }
            }
        }
    }
#endif
