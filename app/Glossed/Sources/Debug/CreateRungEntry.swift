#if DEBUG

    import AddLadder
    import DataKit
    import SwiftUI

    /// Its own file for the same reason `LiveShelfEntry` is: `ScreenEntries`
    /// sits at SwiftLint's file-length ceiling.
    extension LadderFixtures {
        /// All the way down: search, scan, near matches, none of these.
        static func ladderAtCreate(query: String) -> Ladder {
            var ladder = ladderAtNearMatches(query: query)
            ladder.noneOfThese()
            return ladder
        }
    }

    @MainActor
    enum CreateRungEntry {
        static let form = ScreenEntry(
            id: "ladder-create",
            title: "ladder 4 · create it",
            note: "four fields, no review queue. brand is a typeahead FK — type 'rare' and pick; "
                + "no free-text brands, and the button stays down until brand + name + category exist"
        ) {
            CreateRungView(model: CreateRungModel(
                catalog: StubCreateCatalog(),
                shelf: StubLogging(),
                ladder: LadderFixtures.ladderAtCreate(query: "soft pinch liquid blush")
            ))
        }

        static let logFailed = ScreenEntry(
            id: "ladder-create-log-failed",
            title: "ladder 4 · created, but the shelf write failed",
            note: "the GLO-15 quiet failure made visible: the product exists, the shelf row does not, "
                + "and retrying resumes at the log — same product, never a duplicate"
        ) {
            PreCreated(model: CreateRungModel(
                catalog: StubCreateCatalog(),
                shelf: StubLogging(failing: true),
                ladder: LadderFixtures.ladderAtCreate(query: "soft pinch liquid blush")
            ))
        }

        static let confirmed = ScreenEntry(
            id: "ladder-create-confirmed",
            title: "ladder 5 · added, personal scope",
            note: "the deal, stated: yours only until three people log the same product. "
                + "the rail's fourth segment stays current — confirm is not a fifth rung"
        ) {
            PreCreated(model: CreateRungModel(
                catalog: StubCreateCatalog(),
                shelf: StubLogging(),
                ladder: LadderFixtures.ladderAtCreate(query: "soft pinch liquid blush")
            ))
        }

        /// Fills the form and submits once, so the state under test is what the
        /// screen shows *after* the tap — the confirmation, or the failed-log
        /// form with its retry.
        private struct PreCreated: View {
            @State var model: CreateRungModel

            var body: some View {
                CreateRungView(model: model)
                    .task {
                        if let brand = StubCreateCatalog.rareBeauty {
                            model.pick(brand: brand)
                        }
                        await model.loadCategories()
                        if let category = model.categories.first {
                            model.pick(category: category)
                        }
                        model.variantText = "joy · 2.5ml mini"
                        await model.create()
                    }
            }
        }
    }

    // MARK: - Doubles

    /// Wire models have no public inits (they are DataKit's), so fixtures are
    /// decoded — same shape as `stubHit`, same reason, same optional-not-`try!`.
    private func decodedFixture<T: Decodable>(_ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    struct StubCreateCatalog: ProductCreating {
        static let rareBeauty: Brand? = decodedFixture("""
        {"id":"cccccccc-0000-0000-0000-000000000001","name":"rare beauty"}
        """)

        static let brands: [Brand] = [
            Self.rareBeauty,
            decodedFixture("""
            {"id":"cccccccc-0000-0000-0000-000000000002","name":"rhode"}
            """),
            decodedFixture("""
            {"id":"cccccccc-0000-0000-0000-000000000003","name":"rare & co"}
            """)
        ].compactMap(\.self)

        static let categories: [DataKit.Category] = [
            decodedFixture("""
            {"id":"dddddddd-0000-0000-0000-000000000001","domain":"makeup","slug":"blush",
             "label":"blush","wear_in_days":0,"is_anchor":false,"rank_unlock_min":3}
            """),
            decodedFixture("""
            {"id":"dddddddd-0000-0000-0000-000000000002","domain":"makeup","slug":"foundation",
             "label":"foundation","wear_in_days":0,"is_anchor":true,"rank_unlock_min":3}
            """),
            decodedFixture("""
            {"id":"dddddddd-0000-0000-0000-000000000003","domain":"skincare","slug":"cleanser",
             "label":"cleanser","wear_in_days":14,"is_anchor":false,"rank_unlock_min":3}
            """)
        ].compactMap(\.self)

        static let created: CreatedProduct? = decodedFixture("""
        {"product_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "variant_id":"aaaaaaaa-0000-0000-0000-000000000002"}
        """)

        func brands(matching query: String, limit _: Int) async throws(GlossedError) -> [Brand] {
            StubCreateCatalog.brands.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        func categories(domain _: Domain?) async throws(GlossedError) -> [DataKit.Category] {
            StubCreateCatalog.categories
        }

        func createPersonalProduct(_: PersonalProductDraft) async throws(GlossedError) -> CreatedProduct {
            guard let created = StubCreateCatalog.created else {
                throw GlossedError(.unknown, userMessage: "fixture failed to decode")
            }
            return created
        }
    }

    struct StubLogging: ItemLogging {
        var failing = false

        func log(_ draft: LogDraft) async throws(GlossedError) -> UserItem {
            if failing {
                throw GlossedError.offline
            }
            let json = """
            {"id":"\(UUID().uuidString)","user_id":"\(UUID().uuidString)",
             "variant_id":"\(draft.variantID.uuidString)","status":"own",
             "started_on":null,"note":null,"cutout_r2_key":null}
            """
            guard let item: UserItem = decodedFixture(json) else {
                throw GlossedError(.unknown, userMessage: "fixture failed to decode")
            }
            return item
        }
    }

#endif
