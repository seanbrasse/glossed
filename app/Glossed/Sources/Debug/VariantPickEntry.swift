#if DEBUG

    import AddLadder
    import DataKit
    import SwiftUI

    /// Its own file for the same reason `CreateRungEntry` is: `ScreenEntries`
    /// sits at SwiftLint's file-length ceiling.
    ///
    /// The variant-pick sheet has no kit frame (checked Aug 28 — a picked
    /// card in `G.AddLadder` is `()=>go(back)`); these states are what Sean
    /// workshops at review instead.
    @MainActor
    enum VariantPickEntry {
        static let shades = ScreenEntry(
            id: "variant-sheet",
            title: "logging sheet · three shades",
            note: "the GLO-56 pick made real: a hit is a product, a shelf item is a variant. "
                + "nothing preselected — choosing the shade is the point, and the button waits"
        ) {
            sheet(variants: [
                stubVariant(shade: "220", hex: "#E0B891", sizeML: 32),
                stubVariant(shade: "240", hex: "#D9A87E", sizeML: 32),
                stubVariant(shade: "330", hex: "#8C5E3C", sizeML: 32)
            ])
        }

        static let soleVariant = ScreenEntry(
            id: "variant-sheet-single",
            title: "logging sheet · the only one we have",
            note: "one variant is a confirmation, not a choice: preselected, one tap — "
                + "but shown, never silently logged (GLO-56's wrong-shade warning)"
        ) {
            sheet(variants: [stubVariant(sizeML: 150)])
        }

        static let loadFailed = ScreenEntry(
            id: "variant-sheet-failed",
            title: "logging sheet · variants didn't load",
            note: "a failure is not an empty catalog — say so and keep the retry, "
                + "same rule the search rung already follows"
        ) {
            sheet(failure: .offline)
        }

        static let noVariants = ScreenEntry(
            id: "variant-sheet-empty",
            title: "logging sheet · nothing on file",
            note: "a real catalog state (~3 products have no variant rows): an honest dead-stop "
                + "with a way back, not an unpressable button"
        ) {
            sheet(variants: [])
        }

        private static func sheet(
            variants: [Variant?] = [],
            failure: GlossedError? = nil
        ) -> some View {
            let hit = stubHit("soft pinch liquid blush", brand: "rare beauty", category: "blush")
            return ZStack {
                Color.clear
                if let hit {
                    VariantPickSheet(
                        model: VariantPickModel(
                            hit: hit,
                            catalog: StubVariantListing(
                                variants: variants.compactMap(\.self),
                                failure: failure
                            )
                        ),
                        onConfirm: { _ in },
                        onCancel: {}
                    )
                }
            }
        }
    }

    actor StubVariantListing: VariantListing {
        private let variants: [Variant]
        private let failure: GlossedError?

        init(variants: [Variant] = [], failure: GlossedError? = nil) {
            self.variants = variants
            self.failure = failure
        }

        func variants(productID _: UUID) async throws(GlossedError) -> [Variant] {
            if let failure {
                throw failure
            }
            return variants
        }
    }

    /// Same decode-not-construct reasoning as `stubHit`, same crash-free
    /// failure mode: a row that fails to decode thins the sheet, visibly.
    func stubVariant(
        shade: String? = nil,
        hex: String? = nil,
        sizeML: Double? = nil
    ) -> Variant? {
        let shadeField = shade.map { "\"shade_code\":\"\($0)\"," } ?? ""
        let hexField = hex.map { "\"shade_hex\":\"\($0)\"," } ?? ""
        let sizeField = sizeML.map { "\"size_ml\":\($0)," } ?? ""
        let json = """
        {"id":"\(UUID().uuidString)","product_id":"\(UUID().uuidString)",
         \(shadeField)\(hexField)\(sizeField)"gtin":null}
        """
        return try? JSONDecoder().decode(Variant.self, from: Data(json.utf8))
    }
#endif
