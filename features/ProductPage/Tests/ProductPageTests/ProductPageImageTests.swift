import DataKit
import DesignSystem
import Foundation
import Testing
@testable import ProductPage

// GLO-153: tech/01's render rule puts this page on the catalog-image side —
// "product pages/leaderboards/discover/search → catalog image" — and it had no
// image field at all, so the drawn mock was not the chain's floor, it was the
// only branch. The sheet showed the real fenty cutout and the page, one tap
// later, showed a generic pink bottle.

private func item(catalogImageURL: URL? = nil) -> ProductPageItem {
    ProductPageItem(
        variantID: UUID(),
        brand: "fenty beauty",
        name: "pro filt'r soft matte",
        categoryLabel: "foundation",
        variant: "330",
        packaging: .compact,
        catalogImageURL: catalogImageURL
    )
}

@Test func thePageCarriesTheCatalogImageItIsToldAbout() throws {
    // The field the page did not have. Its absence is the whole defect: a
    // hero cannot render an image it was never given.
    let url = try #require(URL(string: "https://example.test/catalog/fenty-330.png"))

    #expect(item(catalogImageURL: url).catalogImageURL == url)
}

@Test func noCatalogImageIsTheChainsFloorAndNotAnError() {
    // Nil must stay legal — the OBF half of the catalog has no image, and a
    // page that refused to render without one would be worse than a mock.
    #expect(item().catalogImageURL == nil)
}

@Test func theImageIsNotRequiredToBuildAPage() {
    // Defaulted, so every existing caller — the debug picker's four fixture
    // states among them — keeps compiling and keeps drawing the mock.
    let untold = ProductPageItem(
        variantID: UUID(),
        brand: "rare beauty",
        name: "soft pinch",
        categoryLabel: "blush"
    )

    #expect(untold.catalogImageURL == nil)
}
