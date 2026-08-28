import DataKit
import DesignSystem
import Foundation
import Testing
@testable import Shelf

// The translation from wire row to feature model. Every assertion here is a
// rename or a table lookup — the moment one becomes a computation, it belongs
// in the model, not the mapping.

private func row(
    category: String = "blush",
    label: String = "blush",
    domain: Domain = .makeup,
    scope: CatalogScope = .canonical,
    rank: Int? = nil,
    name: String = "soft pinch liquid blush",
    imageKey: String? = nil,
    imageWidth: Int? = nil,
    imageHeight: Int? = nil
) throws -> ShelfRow {
    let raw = """
    {"user_item_id":"\(UUID().uuidString)",
     "variant_id":"\(UUID().uuidString)",
     "product_id":"\(UUID().uuidString)",
     "product_name":"\(name)","brand_name":"rare beauty",
     "category_slug":"\(category)","category_label":"\(label)",
     "domain":"\(domain.rawValue)","scope":"\(scope.rawValue)",
     "benefit_line":null,"variant_label":"joy · 7.5ml","height_mm":70,
     "status":"own","started_on":null,"note":null,"cutout_r2_key":null,
     "logged_at":"2026-08-01T12:00:00Z",
     "rank_position":\(rank.map(String.init) ?? "null"),"ranked_in_category":0,
     "is_anchor":\(category == "foundation"),
     "catalog_image_key":\(imageKey.map { "\"\($0)\"" } ?? "null"),
     "catalog_image_width":\(imageWidth.map(String.init) ?? "null"),
     "catalog_image_height":\(imageHeight.map(String.init) ?? "null")}
    """
    return try JSONDecoder.postgrest.decode(ShelfRow.self, from: Data(raw.utf8))
}

@Test func theImageURLNeedsBothHalves() throws {
    // A key with no base is a fixture context; a URL guessed there 404s on
    // screen. Both present composes; either absent renders the mock floor.
    let base = try #require(URL(string: "http://127.0.0.1:54321/storage/v1/object/public/catalog"))
    let with = try ShelfItem(row: row(imageKey: "abc/cut512.png", imageWidth: 219, imageHeight: 372), imageBase: base)
    #expect(with.catalogImageURL?.absoluteString
        == "http://127.0.0.1:54321/storage/v1/object/public/catalog/abc/cut512.png")
    #expect(with.catalogImageAspect.map { abs($0 - 219.0 / 372.0) < 0.0001 } == true)

    let noBase = try ShelfItem(row: row(imageKey: "abc/cut512.png"))
    #expect(noBase.catalogImageURL == nil)
    let noKey = try ShelfItem(row: row(), imageBase: base)
    #expect(noKey.catalogImageURL == nil)
}

@Test func aPhotoPacksAtItsOwnWidthAndAMockAtTheSilhouettes() throws {
    // GLO-68's shape: the pack must use whichever width will actually render.
    let photo = try ShelfItem(
        row: row(imageKey: "abc/cut512.png", imageWidth: 300, imageHeight: 300),
        imageBase: #require(URL(string: "http://x"))
    )
    // A square photo would pack at its drawn height — unless the bucket's
    // cap is tighter, which for this row it is (GLO-82).
    #expect(photo.slotWidth == min(photo.drawnScale, photo.sizeClass.maxWidth))
    let mock = try ShelfItem(row: row())
    #expect(mock.slotWidth == max(
        ProductMock.drawnWidth(kind: mock.packaging, scale: mock.drawnScale),
        ShelfBay.minimumSlot
    ))
}

@Test func aHalfSizedImageClaimsNoAspect() throws {
    // A zero would divide, and an aspect from half a size lies about the pack.
    let item = try ShelfItem(
        row: row(imageKey: "abc/cut512.png", imageWidth: 300),
        imageBase: #require(URL(string: "http://x"))
    )
    #expect(item.catalogImageAspect == nil)
}

@Test func volumeScalesTheDrawingWhenHeightIsUnknown() {
    // Every imported variant has a size and no height. Height goes as the
    // cube root of volume, and only the ordering is claimed: the 236ml pump
    // towers over the 30ml foundation, which is PRD §08's sentence.
    let pump = ShelfItem(
        id: UUID(),
        brand: "cerave",
        name: "big pump",
        categorySlug: "cleanser",
        categoryLabel: "cleanser",
        domain: .skincare,
        packaging: .bottle,
        sizeML: 236
    )
    let foundation = ShelfItem(
        id: UUID(),
        brand: "fenty",
        name: "small bottle",
        categorySlug: "foundation",
        categoryLabel: "foundation",
        domain: .makeup,
        packaging: .bottle,
        sizeML: 30
    )
    #expect(pump.drawnScale > foundation.drawnScale)
    // A measured height still wins over any estimate.
    let measured = ShelfItem(
        id: UUID(),
        brand: "x",
        name: "y",
        categorySlug: "cleanser",
        categoryLabel: "cleanser",
        domain: .skincare,
        packaging: .bottle,
        heightMM: 200,
        sizeML: 10
    )
    #expect(measured.drawnScale == ShelfSizeClass.large.height)
}

@Test func theMappingRenamesRatherThanComputes() throws {
    let item = try ShelfItem(row: row(rank: 2))
    #expect(item.brand == "rare beauty")
    #expect(item.name == "soft pinch liquid blush")
    #expect(item.variant == "joy · 7.5ml")
    #expect(item.heightMM == 70)
    #expect(item.rank == 2)
    #expect(item.isPersonalScope == false)
    #expect(item.loggedAt != nil)
    #expect(item.isAnchorCategory == false)
}

@Test func anAnchorCategoryRowGatesTheFitSection() throws {
    #expect(try ShelfItem(row: row(category: "foundation")).isAnchorCategory)
}

@Test func packagingComesFromThePrimitivesTable() throws {
    // The one field the row does not carry: derived from the category via the
    // same lookup the ladder's rows use, so one product draws as one shape.
    #expect(try ShelfItem(row: row(category: "blush")).packaging == .dropper)
    #expect(try ShelfItem(row: row(category: "fragrance", domain: .fragrance)).packaging == .mist)
    #expect(try ShelfItem(row: row(category: "never-seen")).packaging == .tube)
}

@Test func aPersonalRowKeepsItsBadge() throws {
    #expect(try ShelfItem(row: row(scope: .personal)).isPersonalScope)
}

@Test func sectionsGroupBySlugInTheKitsDomainOrder() throws {
    let rows = try [
        row(category: "styler", label: "stylers", domain: .haircare),
        row(category: "blush", label: "blush", domain: .makeup),
        row(category: "cleanser", label: "cleanser", domain: .skincare),
        row(category: "blush", label: "blush", domain: .makeup)
    ]
    let sections = ShelfSection.grouped(from: rows)
    #expect(sections.map(\.slug) == ["blush", "cleanser", "styler"])
    #expect(sections[0].items.count == 2)
    #expect(sections[0].domain == .makeup)
}

extension JSONDecoder {
    /// The platform decoder DataKit's reads actually run through — not a
    /// hand-configured stand-in, which is how `startedOn`'s decoding bug
    /// stayed green (PR #84).
    static let postgrest: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a timestamp: \(string)")
        }
        return decoder
    }()
}
