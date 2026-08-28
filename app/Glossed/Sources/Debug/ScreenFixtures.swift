#if DEBUG

    import AddLadder
    import DataKit
    import DesignSystem
    import Import
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
#endif
