import DataKit
import DesignSystem
import Foundation

/// One thing you own, as the shelf needs it.
///
/// Feature-owned on purpose. `ShelfRepository.items()` returns `UserItem`,
/// which is a `variantID` and a status — no brand, no name, no category, no
/// height. Nothing in the frozen core can fill this in yet, and the shape of
/// the fix is a joined read rather than five lookups per row, so the shelf
/// declares what it needs and GLO-66 supplies it.
///
/// That seam is deliberately visible: this compiles, renders and is testable
/// with nothing behind it, in the same way `SearchRungModel.pickedProductID`
/// hands off a product and refuses to guess a variant.
public struct ShelfItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let brand: String
    public let name: String
    /// The bay this lands in, and the label written over it.
    public let categorySlug: String
    public let categoryLabel: String
    /// Which domain filter answers for it.
    public let domain: Domain
    /// What it is sold in. Carried rather than derived from the category:
    /// `features/AddLadder` already derives a silhouette from a category slug,
    /// features may not import each other, and duplicating the table is how the
    /// two drift. When the catalog records packaging (GLO-66) both callers read
    /// it instead.
    public let packaging: ProductMock.Kind
    /// `variants.height_mm`. Nullable in the schema and unset by the seed.
    public let heightMM: Double?
    /// Position within its category, when the category has been ranked. Nil is
    /// ordinary — a category under its unlock threshold has no order yet.
    public let rank: Int?
    /// `user_items.created_at` — when this landed on the shelf, which is what
    /// "recent" sorts by. Optional because the joined read that supplies it does
    /// not exist yet (GLO-66); an item with no date sorts last rather than
    /// pretending to be new.
    public let loggedAt: Date?

    public init(
        id: UUID,
        brand: String,
        name: String,
        categorySlug: String,
        categoryLabel: String,
        domain: Domain,
        packaging: ProductMock.Kind,
        heightMM: Double? = nil,
        rank: Int? = nil,
        loggedAt: Date? = nil
    ) {
        self.id = id
        self.brand = brand
        self.name = name
        self.categorySlug = categorySlug
        self.categoryLabel = categoryLabel
        self.domain = domain
        self.packaging = packaging
        self.heightMM = heightMM
        self.rank = rank
        self.loggedAt = loggedAt
    }
}

/// One category's worth of items, before they are cut into bays.
///
/// The domain is on the section rather than read off its first item: a category
/// belongs to exactly one domain, and deriving it from an item means an empty
/// category has no domain at all and quietly disappears from every filter.
public struct ShelfSection: Sendable, Equatable {
    public let slug: String
    public let label: String
    public let domain: Domain
    public let items: [ShelfItem]

    public init(slug: String, label: String, domain: Domain, items: [ShelfItem]) {
        self.slug = slug
        self.label = label
        self.domain = domain
        self.items = items
    }
}

/// One row of objects standing on one ground line.
///
/// A bay holds five. The kit chunks a category across as many bays as it needs
/// and numbers the overflow — `serums + actives`, then `serums + actives · 2` —
/// rather than letting a row scroll sideways, because a shelf you have to
/// scroll horizontally stops reading as a shelf.
public struct ShelfBay: Identifiable, Sendable, Equatable {
    /// Capacity of one bay, from `for (let k=0; k<items.length; k+=5)`.
    public static let capacity = 5

    public let id: String
    public let label: String
    public let items: [ShelfItem]

    /// Chunks each category into bays, in the order the categories are given.
    ///
    /// Empty categories produce no bay at all — an empty ground line labelled
    /// `blush` would claim you own blushes.
    public static func bays(from sections: [ShelfSection]) -> [ShelfBay] {
        sections.flatMap { section in
            stride(from: 0, to: section.items.count, by: capacity).map { start in
                let part = start / capacity
                return ShelfBay(
                    id: "\(section.slug)-\(start)",
                    label: part == 0 ? section.label : "\(section.label) · \(part + 1)",
                    items: Array(section.items[start ..< min(start + capacity, section.items.count)])
                )
            }
        }
    }
}

public extension ShelfItem {
    /// How tall to draw this object, in `ProductMock`'s scale units.
    ///
    /// **The ratios are compressed, and the name says drawn rather than real.**
    /// A 15mm compact next to a 190mm shampoo bottle is a 12× difference; drawn
    /// at 12× either the compact is four points tall or the bottle does not fit
    /// in an 82pt bay. So real millimetres are mapped linearly onto the band the
    /// kit draws in and clamped at both ends. What survives is the ordering and
    /// a visible difference — which is what PRD §08 asks for ("a lipstick is
    /// visibly smaller than a shampoo bottle") — not the true proportion.
    ///
    /// With no measurement, the kit's own per-kind table stands in. It is not a
    /// guess dressed as data: a bottle is drawn taller than a compact because
    /// bottles are taller than compacts, and nothing about the individual
    /// product is being claimed.
    var drawnScale: CGFloat {
        guard let heightMM, heightMM > 0 else { return ShelfItem.kitScale(packaging) }
        let clamped = min(max(heightMM, ShelfItem.shortestMM), ShelfItem.tallestMM)
        let fraction = (clamped - ShelfItem.shortestMM) / (ShelfItem.tallestMM - ShelfItem.shortestMM)
        return ShelfItem.smallestScale + CGFloat(fraction) * (ShelfItem.largestScale - ShelfItem.smallestScale)
    }

    /// A pressed powder compact and a litre shampoo bottle — the ends of what a
    /// beauty shelf actually holds. Outside these the drawing stops changing,
    /// which is better than a travel sample vanishing.
    static let shortestMM: Double = 15
    static let tallestMM: Double = 200

    /// The band the kit draws in, taken from its own per-kind table: nothing is
    /// smaller than a compact and nothing is much taller than a bottle.
    static let smallestScale: CGFloat = 44
    static let largestScale: CGFloat = 88

    /// `kindH` in `G.Shelf`.
    static func kitScale(_ packaging: ProductMock.Kind) -> CGFloat {
        switch packaging {
        case .compact: 44
        case .jar: 50
        case .tube: 62
        case .mist: 66
        case .dropper: 68
        case .bottle: 74
        }
    }
}
