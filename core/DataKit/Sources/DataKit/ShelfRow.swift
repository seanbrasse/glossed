import Foundation

// Split from Models.swift for the 300-line file ceiling when 0015's image
// columns landed — a mechanical move, nothing renamed.

/// One shelf row, joined — `user_shelf_items` (GLO-66).
///
/// `UserItem` is what the table stores: a variant id and a status. This is what
/// a shelf draws, and it is one read rather than five lookups per row.
public struct ShelfRow: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID {
        userItemID
    }

    public let userItemID: UUID
    public let variantID: UUID
    public let productID: UUID
    public let productName: String
    public let brandName: String
    public let categorySlug: String
    public let categoryLabel: String
    public let domain: Domain
    /// `personal` until three people log the same product.
    public let scope: CatalogScope
    public let benefitLine: String?
    public let variantLabel: String?
    /// Real height in mm, so a lipstick draws visibly smaller than a shampoo
    /// bottle. **Nullable and undefaulted**: what to draw for an object of
    /// unknown height is the shelf's decision, not the database's.
    public let heightMM: Double?
    public let status: ItemStatus
    /// See `PostgresDay` — the column is a calendar day, not an instant.
    public var startedOn: Date? {
        PostgresDay.parse(startedOnRaw)
    }

    public let note: String?
    public let cutoutKey: String?
    public let loggedAt: Date
    /// Position within its category at the default scope. Nil is ordinary —
    /// a category under its unlock threshold has no order yet, and that is a
    /// different fact from being placed last.
    public let rankPosition: Int?
    /// The other half of "#2 of 5". Carried on the row so both halves come
    /// from one read and a shelf can never say you are second of five while
    /// showing you three things.
    public let rankedInCategory: Int
    /// Whether this category's shade is meant to match skin — the gate on the
    /// item sheet's fit section (GLO-16).
    public let isAnchor: Bool
    /// The variant's newest catalog cutout, as a storage-relative key
    /// ("<variant_id>/cut512.png"), or nil. The app composes the URL from its
    /// own config — DataKit carries the fact, not the bucket (GLO-74).
    public let catalogImageKey: String?
    /// The cutout's pixel size. The shelf packs bays by drawn width, and a
    /// photo's width is its aspect times the drawn height — packing on the
    /// mock's width while rendering a photo's is GLO-68's overlap again.
    public let catalogImageWidth: Int?
    public let catalogImageHeight: Int?
    /// The variant's volume. Rides the row because with `height_mm` unset
    /// (every imported variant) the shelf can still scale by it — a 236ml
    /// pump should tower over a 30ml foundation. The estimate is the shelf's
    /// rule; the row just carries the number.
    public let sizeML: Double?

    private let startedOnRaw: String?

    enum CodingKeys: String, CodingKey {
        case domain, scope, status, note
        case userItemID = "user_item_id"
        case variantID = "variant_id"
        case productID = "product_id"
        case productName = "product_name"
        case brandName = "brand_name"
        case categorySlug = "category_slug"
        case categoryLabel = "category_label"
        case benefitLine = "benefit_line"
        case variantLabel = "variant_label"
        case heightMM = "height_mm"
        case startedOnRaw = "started_on"
        case cutoutKey = "cutout_r2_key"
        case loggedAt = "logged_at"
        case rankPosition = "rank_position"
        case rankedInCategory = "ranked_in_category"
        case isAnchor = "is_anchor"
        case catalogImageKey = "catalog_image_key"
        case catalogImageWidth = "catalog_image_width"
        case catalogImageHeight = "catalog_image_height"
        case sizeML = "size_ml"
    }
}
