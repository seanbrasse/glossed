import Foundation

/// When a routine runs. Mirrors `routine_slot` — wash day is first-class, not
/// a weekly with a note.
public enum RoutineSlot: String, Codable, Sendable, CaseIterable {
    case am, pm, weekly
    case washDay = "wash_day"

    /// Lowercase UI copy.
    public var label: String {
        switch self {
        case .am: "morning"
        case .pm: "evening"
        case .weekly: "weekly"
        case .washDay: "wash day"
        }
    }
}

/// One row of the routines browse. Every row carries its n — `stepN` and
/// `ownerShelfN` are the evidence behind "this is a real routine by someone
/// with a real shelf", and no row renders without them.
public struct BrowseRoutine: Codable, Sendable, Equatable, Identifiable {
    public let routineID: UUID
    /// Approved title only. A routine whose title is still pending review does
    /// not appear in browse at all — the RPC inner-joins approved
    /// `public_texts`, so there is no unapproved-title state to render.
    public let title: String
    public let slot: RoutineSlot
    public let ownerHandle: String
    public let stepN: Int
    public let ownerShelfN: Int
    /// `started_on` is a Postgres `date`, not a timestamp — the platform
    /// decoder wants a time component and throws on a bare calendar day, so it
    /// arrives as a string and is parsed here. Same treatment as `ShelfRow`;
    /// every `date` column in the schema needs it.
    public var startedOn: Date? {
        PostgresDay.parse(startedOnRaw)
    }

    private let startedOnRaw: String?
    public let createdAt: Date

    public var id: UUID {
        routineID
    }

    enum CodingKeys: String, CodingKey {
        case routineID = "routine_id"
        case title, slot
        case ownerHandle = "owner_handle"
        case stepN = "step_n"
        case ownerShelfN = "owner_shelf_n"
        case startedOnRaw = "started_on"
        case createdAt = "created_at"
    }
}

/// One trending row. Products, not people — nothing here is attributed, which
/// is why nothing here is scope-gated.
public struct TrendingVariant: Codable, Sendable, Equatable, Identifiable {
    public let variantID: UUID
    public let brandName: String
    public let productName: String
    public let shadeCode: String?
    /// How many people logged it inside the window.
    public let nLogs: Int
    /// The threshold, travelling with the row so the client never hard-codes it.
    public let minN: Int
    /// Whether `nLogs` clears `minN`.
    public let meetsMinN: Bool
    /// The period `nLogs` is over. A velocity claim without its window is
    /// meaningless, so the window rides along rather than living in the copy.
    public let windowDays: Int
    public let refreshedAt: Date

    public var id: UUID {
        variantID
    }

    enum CodingKeys: String, CodingKey {
        case variantID = "variant_id"
        case brandName = "brand_name"
        case productName = "product_name"
        case shadeCode = "shade_code"
        case nLogs = "n_logs"
        case minN = "min_n"
        case meetsMinN = "meets_min_n"
        case windowDays = "window_days"
        case refreshedAt = "refreshed_at"
    }

    /// The evidence line for a row that has not cleared the threshold.
    ///
    /// **Min-n is rendered, not hidden** (§4, matching the leaderboard in
    /// `tech/01` §3). A below-threshold row still appears, saying how far along
    /// it is — a young surface should look honest rather than empty. Returning
    /// nil above the threshold is what stops the caller printing it twice.
    public var notEnoughYetLine: String? {
        meetsMinN ? nil : "not enough yet · \(nLogs) of \(minN)"
    }
}

/// One step of someone else's routine, with the product named.
public struct RoutineStep: Codable, Sendable, Equatable, Identifiable {
    public let position: Int
    public let userItemID: UUID
    public let brandName: String
    public let productName: String
    public let variantLabel: String?

    public var id: UUID {
        userItemID
    }

    public init(
        position: Int, userItemID: UUID, brandName: String,
        productName: String, variantLabel: String?
    ) {
        self.position = position
        self.userItemID = userItemID
        self.brandName = brandName
        self.productName = productName
        self.variantLabel = variantLabel
    }
}

/// A routine as a viewer sees it.
public struct RoutineDetail: Sendable, Equatable {
    public let routineID: UUID
    public let title: String
    public let slot: RoutineSlot
    public let startedOn: Date?
    public let steps: [RoutineStep]

    public init(
        routineID: UUID, title: String, slot: RoutineSlot,
        startedOn: Date?, steps: [RoutineStep]
    ) {
        self.routineID = routineID
        self.title = title
        self.slot = slot
        self.startedOn = startedOn
        self.steps = steps
    }
}
