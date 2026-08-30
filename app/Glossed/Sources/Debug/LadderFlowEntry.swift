#if DEBUG

    import AddLadder
    import DataKit
    import DesignSystem
    import SwiftUI

    /// The ladder as one trip, which every other ladder entry in this catalog
    /// deliberately is not (GLO-180).
    ///
    /// The rung entries host `SearchRungView`, `BarcodeRungView`,
    /// `NearMatchRungView` and `CreateRungView` **bare**, so each one shows a
    /// rung and none of them shows a *move between* rungs. Everything that makes
    /// the ladder a ladder lives in `LadderFlowView`: it watches the ladder,
    /// builds the next rung's model with the carried state, and raises the
    /// variant sheet when a rung picks a hit. Until this entry existed, that
    /// code could only be driven through `AppShell` — the local stack up and a
    /// seeded user signed in — which is why nobody drove it.
    ///
    /// Two things the sweep saw before this existed, both artefacts of hosting a
    /// rung bare rather than defects in the app: tapping a search hit did
    /// nothing (`pickedHit` had no observer), and tapping "none of these"
    /// advanced the progress rail while the body stayed on the same rung.
    ///
    /// It matters most for the class of bug the sweep exists to catch.
    /// `docs/ux-state-sweep.md` names GLO-96 — *"the ladder resumed a stale
    /// flow"* — as one of the three that justify the file, and a stale-resume
    /// bug is invisible to any fixture that only ever renders one rung.
    @MainActor
    enum LadderFlowEntry {
        static let wholeTrip = ScreenEntry(
            id: "ladder-flow",
            title: "ladder · the whole trip",
            note: "the only entry that moves BETWEEN rungs — search → scan → near → create, "
                + "and a hit opens the shade pick. every other ladder entry hosts one rung alone"
        ) {
            WholeTrip()
        }

        /// The flow's own ending is `onClose` — in the app that dismisses the
        /// whole ladder, which is what makes a finished trip *look* finished.
        /// Left at its default no-op the sheet simply stays put after "add to
        /// shelf", so the fixture would show a confirm that reads as dead. A
        /// state you can enter and not leave is the one thing the sweep's own
        /// rules forbid, so the entry supplies the ending.
        ///
        /// Restarting on a fresh `id` is not just tidiness: it hands the driver
        /// GLO-96's question — *does reopening resume a stale flow?* — which is
        /// the bug `docs/ux-state-sweep.md` names as one of the three that
        /// justify the file, and which no single-rung fixture can ask at all.
        private struct WholeTrip: View {
            @State private var landed: LoggedShelfItem?
            @State private var runID = UUID()

            var body: some View {
                VStack(spacing: 0) {
                    if let landed {
                        banner(landed)
                    }
                    LadderFlowView(
                        catalog: StubLadderCatalog(),
                        shelf: StubLogging(),
                        onClose: { runID = UUID() },
                        onLogged: { landed = $0 }
                    )
                    .id(runID)
                }
            }

            private func banner(_ item: LoggedShelfItem) -> some View {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LANDED ON THE SHELF").eyebrow(color: Tokens.Cherry.deep)
                    // The ids, because the point of driving the whole trip is
                    // that a *variant* reached the shelf — and whether the
                    // category came with it, which the matched-barcode door
                    // still cannot supply (GLO-80).
                    Text("user_item \(item.userItemID.uuidString.prefix(8)) · category "
                        + (item.categoryID.map { String($0.uuidString.prefix(8)) } ?? "none"))
                        .meta()
                    Text("the ladder restarted — it should come back empty").meta()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Tokens.Space.s3)
                .background(Tokens.Support.butterSoft)
            }
        }
    }

    /// Everything the flow asks of the catalog, in one object.
    ///
    /// `LadderCatalog` is five protocols at once, and the picker already had a
    /// stub for each of them separately. This delegates to the same fixture data
    /// rather than inventing a parallel set, so a rung reached through the trip
    /// shows what that rung's own entry shows — otherwise a difference between
    /// the two would read as a transition bug and be neither.
    ///
    /// An actor for the same reason the others are: the protocols are `Sendable`
    /// and the app talks to a real repository across an actor boundary here.
    actor StubLadderCatalog: CatalogSearching, NearMatching, ProductCreating, VariantListing, VariantLookup {
        private let creating = StubCreateCatalog()
        private let hits: [CatalogHit]
        private let candidates: [NearMatch]

        /// Both fixture sets live on the main actor, so they are read once here
        /// — at construction, from the entry's own `@MainActor` closure —
        /// rather than hopped to on every call.
        @MainActor
        init() {
            hits = LadderFixtures.hits
            candidates = NearMatchFixtures.candidates
        }

        // MARK: Rung 1 — search

        func search(_ query: String, limit _: Int) async throws(GlossedError) -> [CatalogHit] {
            // Filtered, unlike the single-rung stub, and that is the point of
            // this entry. A stub that answers every query identically makes a
            // broken input look like a working one — which is exactly how
            // GLO-176 survived its first drive (twenty-two characters typed,
            // three candidates back, and only one character had landed).
            // Here the results are evidence about what was actually asked.
            guard !query.isEmpty else { return [] }
            return hits.filter { hit in
                hit.name.localizedCaseInsensitiveContains(query)
                    || hit.brandName.localizedCaseInsensitiveContains(query)
            }
        }

        func recordFailedSearch(_: String, domain _: Domain?) async {}

        // MARK: Rung 2 — scan

        /// The simulator has no camera, so this rung always shows its
        /// unsupported-device state and the escape row is the way on. That is
        /// the real path a camera-less device takes, and it is the one that
        /// reaches the near-match rung carrying neither a query nor a GTIN.
        func variant(gtin _: String) async throws(GlossedError) -> Variant? {
            nil
        }

        // MARK: Rung 3 — near matches

        func nearMatches(
            _ query: String, domain _: Domain?, gtin: String?
        ) async throws(GlossedError) -> [NearMatch] {
            // The maker band answers from a GTIN alone (0018), so a scan that
            // missed still gets candidates with no name typed.
            guard !query.isEmpty || gtin != nil else { return [] }
            return candidates
        }

        // MARK: Rung 4 — create

        func brands(matching query: String, limit: Int) async throws(GlossedError) -> [Brand] {
            try await creating.brands(matching: query, limit: limit)
        }

        func categories(domain: Domain?) async throws(GlossedError) -> [DataKit.Category] {
            try await creating.categories(domain: domain)
        }

        func createPersonalProduct(_ draft: PersonalProductDraft) async throws(GlossedError) -> CreatedProduct {
            try await creating.createPersonalProduct(draft)
        }

        // MARK: The variant seam — a picked hit becomes a shelf row

        /// Three shades, ignoring the product id the way `StubVariantListing`
        /// does: the fixture hits carry generated ids, and the sheet's job here
        /// is to prove the pick *arrives*, not to model a catalog.
        func variants(productID _: UUID) async throws(GlossedError) -> [Variant] {
            [
                stubVariant(shade: "220", hex: "#E0B891", sizeML: 32),
                stubVariant(shade: "240", hex: "#D9A87E", sizeML: 32),
                stubVariant(shade: "330", hex: "#8C5E3C", sizeML: 32)
            ].compactMap(\.self)
        }
    }
#endif
