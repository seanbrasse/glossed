import Foundation
import Supabase

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

/// The two browse surfaces: other people's routines, and what is being logged.
///
/// Neither takes a user id. `browse_routines` answers for the caller and
/// applies every exclusion server-side; `trending` is about products and has no
/// viewer at all beyond the cohort filter.
public struct BrowseRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    /// Routines from people who chose to be discoverable, scope-respecting.
    ///
    /// Four exclusions apply and all of them are server-side: scope,
    /// `discoverable`, an unapproved title, and a block in either direction.
    /// An empty result is not distinguishable between them, and must not be —
    /// a screen that explained why a particular routine is missing would leak
    /// the reason.
    ///
    /// The filter values are Regulated. They may travel in this call because
    /// the database needs them; they must NOT travel into an analytics event
    /// beyond `filter_kind` (§2.3).
    public func routines(
        slot: RoutineSlot,
        skinType: String? = nil,
        hairPattern: String? = nil,
        limit: Int = 20,
        cursor: Date? = nil
    ) async throws(GlossedError) -> [BrowseRoutine] {
        _ = try await client.requireUserID()
        var params: [String: String?] = ["p_slot": slot.rawValue, "p_limit": String(limit)]
        params["p_skin_type"] = skinType
        params["p_hair_pattern"] = hairPattern
        params["p_cursor"] = cursor.map { ISO8601DateFormatter().string(from: $0) }
        return try await run {
            try await client.supabase.rpc("browse_routines", params: params).execute().value
        }
    }

    /// What people are logging, over a trailing window.
    ///
    /// Callable signed-out — trending is products, not people. Rows below the
    /// threshold ARE returned, with their n and the threshold, so the client
    /// can render "not enough yet · k of N" rather than showing an empty shelf
    /// that looks broken.
    ///
    /// `skinType` selects a cohort. A rendered count in a cohort has to name
    /// whose n it is (`domain.md` §5's companion rule) — the value passed here
    /// is the label, and the two must come from the same place rather than
    /// being typed twice.
    public func trending(skinType: String? = nil, limit: Int = 20) async throws(GlossedError) -> [TrendingVariant] {
        var params: [String: String?] = ["p_limit": String(limit)]
        params["p_skin_type"] = skinType
        return try await run {
            try await client.supabase.rpc("trending", params: params).execute().value
        }
    }

    private func run<T>(_ work: () async throws -> T) async throws(GlossedError) -> T {
        do {
            return try await work()
        } catch {
            throw GlossedError.from(error)
        }
    }
}
