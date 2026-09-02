import Foundation

// The wire between this feature and the `stylist` Edge Function
// (supabase/functions/stylist/tools.ts). DataKit stays ignorant of payload
// shapes — the feature that knows what the function returns owns the
// decoding — so these live here and must stay in step with `tools.ts`.

/// One turn of the thread as the server sees it: text only. Artifacts are
/// not replayed; the model rebuilds them from the shelf every turn.
public struct StylistTranscriptTurn: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case user, assistant
    }

    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public struct StylistTurnRequest: Encodable, Sendable {
    public let messages: [StylistTranscriptTurn]

    public init(messages: [StylistTranscriptTurn]) {
        self.messages = messages
    }
}

/// A routine the stylist proposes, built only from the person's own
/// `user_items` — the server refuses any other id. Saveable as-is.
public struct RoutineDraftBlock: Codable, Sendable, Equatable, Hashable {
    public struct Step: Codable, Sendable, Equatable, Hashable {
        public let userItemID: UUID
        public let productName: String
        public let brandName: String
        public let categoryLabel: String
        public let note: String?

        enum CodingKeys: String, CodingKey {
            case userItemID = "user_item_id"
            case productName = "product_name"
            case brandName = "brand_name"
            case categoryLabel = "category_label"
            case note
        }
    }

    public struct Gap: Codable, Sendable, Equatable, Hashable {
        public let categoryLabel: String
        public let reason: String

        enum CodingKeys: String, CodingKey {
            case categoryLabel = "category_label"
            case reason
        }
    }

    public let title: String
    public let slot: String
    public let targets: [String]
    public let steps: [Step]
    public let gap: Gap?
}

public struct ProductListBlock: Codable, Sendable, Equatable, Hashable {
    public struct Product: Codable, Sendable, Equatable, Hashable, Identifiable {
        public var id: UUID {
            productID
        }

        public let productID: UUID
        public let name: String
        public let brandName: String
        public let categorySlug: String
        public let onShelf: Bool
        public let rankPosition: Int?
        public let rankedInCategory: Int?
        public let faceOffCount: Int?
        public let catalogImageKey: String?
        /// Whose receipt the row carries and its n — "face-offs by people
        /// who wear your shade" · 12 — as the server decided it. Nil when
        /// the evidence is the shelf's own rank, or the catalog's face-offs.
        public let basisLabel: String?
        public let basisN: Int?

        enum CodingKeys: String, CodingKey {
            case productID = "product_id"
            case name
            case brandName = "brand_name"
            case categorySlug = "category_slug"
            case onShelf = "on_shelf"
            case rankPosition = "rank_position"
            case rankedInCategory = "ranked_in_category"
            case faceOffCount = "n_face_offs"
            case catalogImageKey = "catalog_image_key"
            case basisLabel = "basis_label"
            case basisN = "basis_n"
        }
    }

    public let reason: String
    public let products: [Product]
}

public struct LookRefBlock: Codable, Sendable, Equatable, Hashable {
    public let lookID: UUID
    public let caption: String?
    public let photoN: Int

    enum CodingKeys: String, CodingKey {
        case lookID = "look_id"
        case caption
        case photoN = "photo_n"
    }
}

public struct CollectionRefBlock: Codable, Sendable, Equatable, Hashable {
    public let collectionID: UUID
    public let title: String
    public let itemN: Int

    enum CodingKeys: String, CodingKey {
        case collectionID = "collection_id"
        case title
        case itemN = "item_n"
    }
}

/// What a reply can carry besides words. An unknown `type` decodes to nil
/// and is skipped: a server one release ahead must not blank the thread.
public enum StylistBlock: Sendable, Equatable, Hashable {
    case routine(RoutineDraftBlock)
    case products(ProductListBlock)
    case look(LookRefBlock)
    case collection(CollectionRefBlock)

    struct Envelope: Decodable {
        let block: StylistBlock?

        private enum Keys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let type = try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .type)
            let single = try decoder.singleValueContainer()
            switch type {
            case "routine_draft": block = try .routine(single.decode(RoutineDraftBlock.self))
            case "product_list": block = try .products(single.decode(ProductListBlock.self))
            case "look_ref": block = try .look(single.decode(LookRefBlock.self))
            case "collection_ref": block = try .collection(single.decode(CollectionRefBlock.self))
            default: block = nil
            }
        }
    }
}

public struct StylistReply: Decodable, Sendable, Equatable {
    public let text: String
    public let blocks: [StylistBlock]
    public let chips: [String]
    public let groundedIn: [String]
    public let toolsUsed: [String]

    enum CodingKeys: String, CodingKey {
        case text, blocks, chips
        case groundedIn = "grounded_in"
        case toolsUsed = "tools_used"
    }

    public init(text: String, blocks: [StylistBlock], chips: [String], groundedIn: [String], toolsUsed: [String]) {
        self.text = text
        self.blocks = blocks
        self.chips = chips
        self.groundedIn = groundedIn
        self.toolsUsed = toolsUsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        let envelopes = try container.decodeIfPresent([StylistBlock.Envelope].self, forKey: .blocks)
        blocks = envelopes?.compactMap(\.block) ?? []
        chips = try container.decodeIfPresent([String].self, forKey: .chips) ?? []
        groundedIn = try container.decodeIfPresent([String].self, forKey: .groundedIn) ?? []
        toolsUsed = try container.decodeIfPresent([String].self, forKey: .toolsUsed) ?? []
    }

    public static func decode(_ data: Data) throws -> StylistReply {
        try JSONDecoder().decode(StylistReply.self, from: data)
    }
}

/// The function's non-answers, as it states them.
public enum StylistError: Error, Sendable, Equatable {
    /// 08 §3: adults only until Sean rules on minors.
    case notYet
    /// No key on this stack — the tab says so rather than spinning.
    case unconfigured
}
