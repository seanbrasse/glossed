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
    name: String = "soft pinch liquid blush"
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
     "is_anchor":\(category == "foundation")}
    """
    return try JSONDecoder.postgrest.decode(ShelfRow.self, from: Data(raw.utf8))
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
