import Foundation

// Wire models. Names match `docs/domain.md` exactly — face-off, chip, anchor,
// fit, UserItem — so the schema, the API, and conversation all agree.

public enum Domain: String, Codable, Sendable, CaseIterable {
    case makeup, skincare, haircare, fragrance
}

public enum CatalogScope: String, Codable, Sendable {
    case personal, submitted, canonical
}

public enum ItemStatus: String, Codable, Sendable {
    case wantToTry = "want_to_try"
    case own, finished, repurchased
}

/// The six fit answers. Mirrors `fit_enum` — a mismatch here is a bug, and the
/// DesignSystem's FitControl is tested against this list.
public enum Fit: String, Codable, Sendable, CaseIterable {
    case justRight = "just_right"
    case tooLight = "too_light"
    case tooDark = "too_dark"
    case tooPink = "too_pink"
    case tooYellow = "too_yellow"
    case tooOrange = "too_orange"

    /// Lowercase UI copy, per the kit's voice.
    public var label: String {
        switch self {
        case .justRight: "just right"
        case .tooLight: "too light"
        case .tooDark: "too dark"
        case .tooPink: "too pink"
        case .tooYellow: "too yellow"
        case .tooOrange: "too orange"
        }
    }
}

/// A Postgres `date` as it arrives on the wire: `"2026-08-01"`, a calendar day
/// with no time and no zone.
///
/// It needs handling of its own because the platform decoder parses
/// *timestamps* only — it tries `year().month().day()` **plus** a time, and a
/// bare day throws. So a `Date?` bound straight to a `date` column has never
/// been able to decode a row that had one; `UserItem.startedOn` is that bug,
/// and it would have surfaced the first time anyone logged a product with a
/// wear-in period.
///
/// Midnight is resolved in the *current* calendar rather than UTC, because the
/// only consumer is `ShelfRepository.week`, which asks `startOfDay` in the
/// current calendar — pinning to UTC would move a user west of Greenwich onto
/// the previous day and shift every week boundary by one.
enum PostgresDay {
    static func parse(_ raw: String?) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        let parts = raw.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        return Calendar(identifier: .gregorian)
            .date(from: DateComponents(timeZone: .current, year: year, month: month, day: day))
    }
}

public struct Brand: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
}

public struct Category: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let domain: Domain
    public let slug: String
    public let label: String
    /// Days before this category can be ranked — 0 means immediately.
    public let wearInDays: Int
    /// Anchor categories are meant to match skin, so their shade is evidence.
    public let isAnchor: Bool
    public let rankUnlockMin: Int

    enum CodingKeys: String, CodingKey {
        case id, domain, slug, label
        case wearInDays = "wear_in_days"
        case isAnchor = "is_anchor"
        case rankUnlockMin = "rank_unlock_min"
    }
}

public struct Product: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let brandID: UUID
    public let categoryID: UUID
    public let domain: Domain
    public let name: String
    public let benefitLine: String?
    public let scope: CatalogScope

    enum CodingKeys: String, CodingKey {
        case id, domain, name, scope
        case brandID = "brand_id"
        case categoryID = "category_id"
        case benefitLine = "benefit_line"
    }
}

public struct Variant: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let productID: UUID
    public let shadeCode: String?
    public let shadeHex: String?
    public let sizeML: Double?
    public let gtin: String?
    /// Real height in mm — the shelf scales cutouts by this so a lipstick is
    /// visibly smaller than a shampoo bottle (ADR 0004).
    public let heightMM: Double?
    public let priceCents: Int?

    enum CodingKeys: String, CodingKey {
        case id, gtin
        case productID = "product_id"
        case shadeCode = "shade_code"
        case shadeHex = "shade_hex"
        case sizeML = "size_ml"
        case heightMM = "height_mm"
        case priceCents = "price_cents"
    }
}

/// A search hit: the product with the bits needed to render a result card.
public struct CatalogHit: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let brandName: String
    public let categorySlug: String
    public let domain: Domain
    public let scope: CatalogScope
    /// How many face-offs this product has been through, across everyone.
    /// **Nil means unknown, not zero** — an absent aggregate row is not the
    /// claim "nobody has tried this", and a card must omit the evidence line
    /// rather than write `n = 0` (GLO-63).
    public let faceOffCount: Int?
    /// The shade-or-size line — "joy · 7.5ml". Supplied only when the product
    /// has exactly one variant: a three-shade foundation cannot say which
    /// shade a search row is, and naming one of three is worse than naming none.
    public let variantLabel: String?

    enum CodingKeys: String, CodingKey {
        case id, name, domain, scope
        case brandName = "brand_name"
        case categorySlug = "category_slug"
        case faceOffCount = "n_face_offs"
        case variantLabel = "variant_label"
    }
}

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
    }
}

/// What `create_personal_product` returns: the product, and the variant that
/// makes it loggable. Both, or neither — the two inserts are one statement.
public struct CreatedProduct: Codable, Sendable, Hashable {
    public let productID: UUID
    public let variantID: UUID

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case variantID = "variant_id"
    }
}

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
    }
}

public struct UserItem: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let userID: UUID
    public let variantID: UUID
    public let status: ItemStatus
    /// See `PostgresDay` — the column is a calendar day, not an instant. Bound
    /// directly to `Date?` this threw on every row that had one.
    public var startedOn: Date? {
        PostgresDay.parse(startedOnRaw)
    }

    public let note: String?
    public let cutoutKey: String?

    private let startedOnRaw: String?

    enum CodingKeys: String, CodingKey {
        case id, status, note
        case userID = "user_id"
        case variantID = "variant_id"
        case startedOnRaw = "started_on"
        case cutoutKey = "cutout_r2_key"
    }
}

/// What onboarding's payoff screen gets back. The client shows a match claim
/// only when `evidenceBacked` — one weak early recommendation poisons every
/// good one after it (tech/01 §2).
public struct PayoffEvidence: Codable, Sendable {
    public let exactShadeCount: Int
    public let withFitCount: Int
    public let evidenceBacked: Bool

    public init(exactShadeCount: Int, withFitCount: Int, evidenceBacked: Bool) {
        self.exactShadeCount = exactShadeCount
        self.withFitCount = withFitCount
        self.evidenceBacked = evidenceBacked
    }

    enum CodingKeys: String, CodingKey {
        case exactShadeCount = "n_exact_shade"
        case withFitCount = "n_with_fit"
        case evidenceBacked = "evidence_backed"
    }
}
