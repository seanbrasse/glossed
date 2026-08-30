import Foundation

// The shelf's wire formats: what actually goes over the connection, separate
// from the public models callers hold. Internal on purpose — a column rename
// should never be a source-breaking change for a feature package.

struct LogRow: Encodable, Sendable {
    let userID: String
    let variantID: String
    let status: String
    let startedOn: String?
    let note: String?
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case status, note
        case userID = "user_id"
        case variantID = "variant_id"
        case startedOn = "started_on"
        case clientID = "client_id"
    }
}

struct ItemChipRow: Encodable, Sendable {
    let userID: String
    let userItemID: String
    let experienceChipID: String
    let week: Int?

    enum CodingKeys: String, CodingKey {
        case week
        case userID = "user_id"
        case userItemID = "user_item_id"
        case experienceChipID = "experience_chip_id"
    }
}

struct FitOnlyRow: Decodable, Sendable {
    let fit: Fit
}

struct CaptureFitParams: Encodable, Sendable {
    let userItemID: String
    let fits: [String]
    let season: String?

    enum CodingKeys: String, CodingKey {
        case userItemID = "p_user_item_id"
        case fits = "p_fits"
        case season = "p_season"
    }
}

/// Explicit encoders, not the synthesized ones. Swift synthesizes
/// `encodeIfPresent` for optional properties, which DROPS the key when the
/// value is nil — and a PATCH with no keys is a successful no-op. That would
/// make "clear the note" and "clear the like" silently do nothing while every
/// layer above reported success. `encodeNil` is the difference between an
/// update and a lie.
struct NoteUpdate: Encodable, Sendable {
    let note: String?

    enum CodingKeys: String, CodingKey {
        case note
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let note {
            try container.encode(note, forKey: .note)
        } else {
            try container.encodeNil(forKey: .note)
        }
    }
}

struct LikeStateUpdate: Encodable, Sendable {
    let likeState: Int?

    enum CodingKeys: String, CodingKey {
        case likeState = "like_state"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let likeState {
            try container.encode(likeState, forKey: .likeState)
        } else {
            try container.encodeNil(forKey: .likeState)
        }
    }
}

struct LikeStateRow: Decodable, Sendable {
    let likeState: LikeState?

    enum CodingKeys: String, CodingKey {
        case likeState = "like_state"
    }
}

/// The four columns needed to NAME a shelf item, off `user_shelf_items`.
///
/// Top-level rather than nested in one repository because two read it —
/// `BrowseRepository.routineDetail` (someone else's routine) and
/// `RoutinesRepository.mine` (your own). A second copy would be a second place
/// for the wire words to drift, which is the reason `RoutineSlot` is not
/// redeclared either. The view is `security_invoker`, so both callers inherit
/// the shelf policies rather than re-implementing them.
struct ShelfNameRow: Decodable, Sendable {
    let userItemID: UUID
    let brandName: String
    let productName: String
    let variantLabel: String?

    enum CodingKeys: String, CodingKey {
        case userItemID = "user_item_id"
        case brandName = "brand_name"
        case productName = "product_name"
        case variantLabel = "variant_label"
    }
}
