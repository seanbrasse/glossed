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

    enum CodingKeys: String, CodingKey {
        case id, name, domain, scope
        case brandName = "brand_name"
        case categorySlug = "category_slug"
    }
}

public struct UserItem: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let userID: UUID
    public let variantID: UUID
    public let status: ItemStatus
    public let startedOn: Date?
    public let note: String?
    public let cutoutKey: String?

    enum CodingKeys: String, CodingKey {
        case id, status, note
        case userID = "user_id"
        case variantID = "variant_id"
        case startedOn = "started_on"
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

    enum CodingKeys: String, CodingKey {
        case exactShadeCount = "n_exact_shade"
        case withFitCount = "n_with_fit"
        case evidenceBacked = "evidence_backed"
    }
}
