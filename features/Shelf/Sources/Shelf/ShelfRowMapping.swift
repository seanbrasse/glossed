import DataKit
import DesignSystem
import Foundation

// The seam closes: GLO-66's joined read exists (`user_shelf_items`, PR #82) and
// DataKit selects it (`ShelfRepository.shelf()`, PR #84). What is left is the
// translation from the wire row to the feature's own model, which is this file
// — and it stays a translation, not a second model: every field is a rename or
// a table lookup, never a computation the view would then disagree with.

public extension ShelfItem {
    /// One shelf row, as the wire carries it.
    ///
    /// `packaging` is the one field the row does not supply — the catalog
    /// records no packaging (GLO-14) — so it is derived from the category via
    /// the primitive's own table, the same lookup the ladder's match rows use.
    init(row: ShelfRow) {
        self.init(
            id: row.userItemID,
            brand: row.brandName,
            name: row.productName,
            categorySlug: row.categorySlug,
            categoryLabel: row.categoryLabel,
            domain: row.domain,
            variant: row.variantLabel,
            packaging: ProductMock.Kind.usual(forCategory: row.categorySlug),
            heightMM: row.heightMM,
            benefitLine: row.benefitLine,
            status: row.status,
            startedOn: row.startedOn,
            isPersonalScope: row.scope == .personal,
            rank: row.rankPosition,
            loggedAt: row.loggedAt
        )
    }
}

public extension ShelfSection {
    /// Groups wire rows into the sections the shelf renders, in the order the
    /// bays should appear: by domain in the kit's order (makeup first, the
    /// most-logged), then by label within a domain.
    ///
    /// Grouped by slug, not label — two categories could share a label some
    /// day, and a bay that merged them would mix two rank lists.
    static func grouped(from rows: [ShelfRow]) -> [ShelfSection] {
        let byCategory = Dictionary(grouping: rows, by: \.categorySlug)
        return byCategory.values
            .compactMap { group -> ShelfSection? in
                guard let first = group.first else { return nil }
                return ShelfSection(
                    slug: first.categorySlug,
                    label: first.categoryLabel,
                    domain: first.domain,
                    items: group.map(ShelfItem.init(row:))
                )
            }
            .sorted { lhs, rhs in
                let lhsDomain = ShelfModel.domains.firstIndex(of: lhs.domain) ?? .max
                let rhsDomain = ShelfModel.domains.firstIndex(of: rhs.domain) ?? .max
                if lhsDomain != rhsDomain {
                    return lhsDomain < rhsDomain
                }
                return lhs.label < rhs.label
            }
    }
}
