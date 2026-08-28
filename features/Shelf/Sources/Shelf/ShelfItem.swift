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
    /// The shade or size, as the row writes it — "joy · 7.5ml". Optional because
    /// a search hit is a product and the variant text is one of the three facts
    /// the catalog does not return yet (GLO-63); a row with none says the
    /// product's name and stops rather than inventing a size.
    public let variant: String?
    /// What it is sold in. Carried rather than derived from the category:
    /// `features/AddLadder` already derives a silhouette from a category slug,
    /// features may not import each other, and duplicating the table is how the
    /// two drift. When the catalog records packaging (GLO-66) both callers read
    /// it instead.
    public let packaging: ProductMock.Kind
    /// `variants.height_mm`. Nullable in the schema and unset by the seed.
    public let heightMM: Double?
    /// `products.benefit_line` — the one sentence the sheet leads with.
    public let benefitLine: String?
    public let status: ItemStatus
    /// `user_items.started_on`. Set for things with a wear-in period, which is
    /// what turns the status line into "week 3".
    public let startedOn: Date?
    /// Personal scope: yours alone until three people log the same product.
    public let isPersonalScope: Bool
    /// Position within its category, when the category has been ranked. Nil is
    /// ordinary — a category under its unlock threshold has no order yet.
    public let rank: Int?
    /// `user_items.created_at` — when this landed on the shelf, which is what
    /// "recent" sorts by. Optional because the joined read that supplies it does
    /// not exist yet (GLO-66); an item with no date sorts last rather than
    /// pretending to be new.
    public let loggedAt: Date?
    /// Whether the category's shade is meant to match skin — the gate on the
    /// sheet's fit section. Shade is only evidence where it is meant to match.
    public let isAnchorCategory: Bool
    /// The variant's volume, for the height estimate when `heightMM` is
    /// unset — which is every imported variant today.
    public let sizeML: Double?
    /// The variant's catalog cutout, already resolved to a URL by whoever
    /// built the item — the feature knows nothing about buckets (GLO-74).
    /// Nil renders the drawn mock, which is the chain's floor, not an error.
    public let catalogImageURL: URL?
    /// That image's width over height. Carried because the bay packs by drawn
    /// width, and a photo's width is its aspect times the drawn height —
    /// packing on the mock's width while rendering a photo's is GLO-68 again.
    public let catalogImageAspect: Double?

    public init(
        id: UUID,
        brand: String,
        name: String,
        categorySlug: String,
        categoryLabel: String,
        domain: Domain,
        variant: String? = nil,
        packaging: ProductMock.Kind,
        heightMM: Double? = nil,
        benefitLine: String? = nil,
        status: ItemStatus = .own,
        startedOn: Date? = nil,
        isPersonalScope: Bool = false,
        rank: Int? = nil,
        loggedAt: Date? = nil,
        isAnchorCategory: Bool = false,
        sizeML: Double? = nil,
        catalogImageURL: URL? = nil,
        catalogImageAspect: Double? = nil
    ) {
        self.id = id
        self.brand = brand
        self.name = name
        self.categorySlug = categorySlug
        self.categoryLabel = categoryLabel
        self.domain = domain
        self.variant = variant
        self.packaging = packaging
        self.heightMM = heightMM
        self.benefitLine = benefitLine
        self.status = status
        self.startedOn = startedOn
        self.isPersonalScope = isPersonalScope
        self.rank = rank
        self.loggedAt = loggedAt
        self.isAnchorCategory = isAnchorCategory
        self.sizeML = sizeML
        self.catalogImageURL = catalogImageURL
        self.catalogImageAspect = catalogImageAspect
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
    /// The gap between two objects standing on the same shelf, from the kit.
    public static let itemGap: CGFloat = 10

    /// No object occupies less than this much shelf, however narrow it is drawn.
    ///
    /// A tube draws 17pt wide and its rank sticker is about 24 — "#100" nearer
    /// 28. The sticker is centred on the object and is allowed to overhang it
    /// (that is what a label does), but once bays are packed by width rather
    /// than capped at five, two narrow neighbours put their stickers on top of
    /// each other. This is the floor that keeps them apart, and it is the
    /// shelf's business rather than `ProductMock`'s: the number depends on what
    /// the labels say, and only the shelf knows that they are ranks.
    public static let minimumSlot: CGFloat = 30

    public let id: String
    public let label: String
    public let items: [ShelfItem]

    /// Chunks each category into bays that fill the shelf, in the order the
    /// categories are given.
    ///
    /// A bay takes items until the next one would not fit, then starts a new
    /// one. **Measured, not divided**: a bay holding a compact, a tube and a
    /// jar has no single item width, so capacity is a running total.
    ///
    /// Empty categories produce no bay at all — an empty ground line labelled
    /// `blush` would claim you own blushes.
    ///
    /// - Parameter width: the space inside a bay's own padding. Capacity — and
    ///   so the `blush · 2` labels — therefore depends on the device, which is
    ///   the honest behaviour for a shelf and is worth knowing before comparing
    ///   two screenshots (GLO-68).
    public static func bays(from sections: [ShelfSection], fittingWidth width: CGFloat) -> [ShelfBay] {
        sections.flatMap { section in
            chunks(of: section.items, fittingWidth: width).enumerated().map { part, items in
                ShelfBay(
                    id: "\(section.slug)-\(part)",
                    label: part == 0 ? section.label : "\(section.label) · \(part + 1)",
                    items: items
                )
            }
        }
    }

    /// The packing itself, kept separate so it can be checked without labels
    /// or sections in the way.
    ///
    /// Every bay holds at least one item even when that item is wider than the
    /// shelf. An object too big for its shelf should hang over the edge; a bay
    /// that refused it would drop it from the screen entirely.
    static func chunks(of items: [ShelfItem], fittingWidth width: CGFloat) -> [[ShelfItem]] {
        var bays: [[ShelfItem]] = []
        var current: [ShelfItem] = []
        var used: CGFloat = 0

        for item in items {
            let slot = item.slotWidth
            let needed = current.isEmpty ? slot : used + itemGap + slot
            if !current.isEmpty, needed > width {
                bays.append(current)
                current = [item]
                used = slot
            } else {
                current.append(item)
                used = needed
            }
        }
        if !current.isEmpty {
            bays.append(current)
        }
        return bays
    }
}

public extension ShelfItem {
    /// What the sheet writes after the variant: "week 3" while something is
    /// wearing in, otherwise the status itself.
    ///
    /// The week is not stored. `ShelfRepository.week(startedOn:loggedOn:)` in
    /// the frozen core already owns that arithmetic — and it has to, because
    /// `item_chips.week` is stamped by the same rule. Two implementations of
    /// "which week is this" would let a chip say week 1 while the shelf says
    /// week 2 about the same product on the same day.
    func statusLabel(on day: Date = Date()) -> String {
        guard let week = ShelfRepository.week(startedOn: startedOn, loggedOn: day) else {
            return ShelfItem.label(for: status)
        }
        return "week \(week)"
    }

    /// Lowercase, per the kit's voice. An exhaustive switch rather than a
    /// `rawValue` tidy-up, so a new status is a compile error here instead of
    /// `want_to_try` appearing on a shelf with its underscore showing.
    static func label(for status: ItemStatus) -> String {
        switch status {
        case .wantToTry: "want to try"
        case .own: "own"
        case .finished: "finished"
        case .repurchased: "repurchased"
        }
    }
}
