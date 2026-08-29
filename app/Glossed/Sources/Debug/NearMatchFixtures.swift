#if DEBUG

    import AddLadder
    import DataKit
    import Foundation

    /// Its own file for the same reason the other entry files are:
    /// `ScreenData` and `ScreenEntries` both sit at the file-length ceiling.
    ///
    /// Near matches decode off the wire like every other fixture — and each
    /// carries its band's reason (0018), which is what the rung is *for*.
    actor StubNearMatching: NearMatching {
        private let matches: [NearMatch]

        init(matches: [NearMatch]) {
            self.matches = matches
        }

        func nearMatches(
            _: String, domain _: Domain?, gtin _: String?
        ) async throws(GlossedError) -> [NearMatch] {
            matches
        }
    }

    func stubNearMatch(_ name: String, brand: String, category: String, why: String) -> NearMatch? {
        let json = """
        {"id":"\(UUID().uuidString)","name":"\(name)","brand_name":"\(brand)",
         "category_id":"\(UUID().uuidString)","category_slug":"\(category)",
         "domain":"makeup","scope":"canonical","why":"\(why)"}
        """
        return try? JSONDecoder().decode(NearMatch.self, from: Data(json.utf8))
    }

    /// The kit's own three confusions, now with their computed reasons.
    @MainActor
    enum NearMatchFixtures {
        static let candidates: [NearMatch] = [
            stubNearMatch(
                "soft pinch liquid blush", brand: "rare beauty", category: "blush",
                why: "similar name — check the shade and size"
            ),
            stubNearMatch(
                "soft pinch tinted moisturizer", brand: "rare beauty", category: "foundation",
                why: "same brand — different product"
            ),
            stubNearMatch(
                "soft pinch luminous blush", brand: "rare beauty", category: "blush",
                why: "same maker as your scan"
            )
        ].compactMap(\.self)
    }

#endif
