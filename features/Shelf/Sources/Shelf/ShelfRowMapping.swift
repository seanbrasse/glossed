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
    /// - Parameter imageBase: the public base URL for catalog cutouts (the
    ///   app's config knows the stack; the row carries only a storage key).
    ///   Nil renders mocks — the fixture states pass nothing and lose nothing.
    init(row: ShelfRow, imageBase: URL? = nil) {
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
            note: row.note,
            status: row.status,
            startedOn: row.startedOn,
            isPersonalScope: row.scope == .personal,
            rank: row.rankPosition,
            loggedAt: row.loggedAt,
            isAnchorCategory: row.isAnchor,
            sizeML: row.sizeML,
            catalogImageURL: ShelfItem.imageURL(base: imageBase, key: row.catalogImageKey),
            catalogImageAspect: ShelfItem.aspect(width: row.catalogImageWidth, height: row.catalogImageHeight),
            variantID: row.variantID
        )
    }

    /// Composed only when both halves exist — a key with no base is a fixture
    /// context, and a URL guessed there would 404 on screen.
    static func imageURL(base: URL?, key: String?) -> URL? {
        guard let base, let key else { return nil }
        return base.appending(path: key)
    }

    /// Width over height, only when both are real — a zero would divide, and
    /// an aspect from half a size is a lie about the pack width.
    static func aspect(width: Int?, height: Int?) -> Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }
}

public extension ShelfSection {
    /// Groups wire rows into the sections the shelf renders, in the order the
    /// bays should appear: by domain in the kit's order (makeup first, the
    /// most-logged), then by label within a domain.
    ///
    /// Grouped by slug, not label — two categories could share a label some
    /// day, and a bay that merged them would mix two rank lists.
    static func grouped(from rows: [ShelfRow], imageBase: URL? = nil) -> [ShelfSection] {
        let byCategory = Dictionary(grouping: rows, by: \.categorySlug)
        return byCategory.values
            .compactMap { group -> ShelfSection? in
                guard let first = group.first else { return nil }
                return ShelfSection(
                    slug: first.categorySlug,
                    label: first.categoryLabel,
                    domain: first.domain,
                    items: group.map { ShelfItem(row: $0, imageBase: imageBase) }
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
