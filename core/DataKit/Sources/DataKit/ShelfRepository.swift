import Foundation
import Supabase

/// The user's own shelf: items, chips, fits. Every call is scoped to the signed-in
/// user by RLS; `requireUserID()` fails fast rather than issuing a query that
/// would silently return nothing.
public struct ShelfRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    public func items(status: ItemStatus? = nil) async throws(GlossedError) -> [UserItem] {
        _ = try await client.requireUserID()
        return try await run {
            let base = client.supabase.from("user_items").select().is("deleted_at", value: nil)
            let filtered = status.map { base.eq("status", value: $0.rawValue) } ?? base
            return try await filtered.order("created_at", ascending: false).execute().value
        }
    }

    /// The shelf, as it is drawn: one read of `user_shelf_items`, which joins
    /// `user_items → variants → products → brands → categories` and carries the
    /// rank. `items(status:)` above returns the raw table rows — a variant id
    /// and a status — which is enough to count what you own and nothing else.
    public func shelf(status: ItemStatus? = nil) async throws(GlossedError) -> [ShelfRow] {
        _ = try await client.requireUserID()
        return try await run {
            let base = client.supabase.from("user_shelf_items").select()
            let filtered = status.map { base.eq("status", value: $0.rawValue) } ?? base
            return try await filtered.order("logged_at", ascending: false).execute().value
        }
    }

    /// Logs a product. `clientID` makes this idempotent: a double-tap or a retry
    /// on a bad connection is a no-op rather than a duplicate shelf entry.
    public func log(_ draft: LogDraft) async throws(GlossedError) -> UserItem {
        let userID = try await client.requireUserID()
        return try await run {
            try await client.supabase
                .from("user_items")
                .upsert(draft.row(userID: userID), onConflict: "client_id")
                .select()
                .single()
                .execute()
                .value
        }
    }

    /// Applies an experience chip. Skincare reactions carry a week stamp —
    /// "broke me out · week 1" and "· week 10" are opposite facts, so the week
    /// is derived from `started_on` rather than typed.
    public func applyChip(
        itemID: UUID,
        chipID: UUID,
        startedOn: Date? = nil,
        loggedOn: Date = Date()
    ) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        let row = ItemChipRow(
            userID: userID.uuidString,
            userItemID: itemID.uuidString,
            experienceChipID: chipID.uuidString,
            week: ShelfRepository.week(startedOn: startedOn, loggedOn: loggedOn)
        )
        try await run {
            _ = try await client.supabase
                .from("item_chips")
                .upsert(row, onConflict: "user_item_id,experience_chip_id")
                .execute()
        }
    }

    /// Week 1 is the first seven days from `started_on`. Nil when the product
    /// has no start date (makeup, fragrance — nothing to wear in).
    public static func week(startedOn: Date?, loggedOn: Date) -> Int? {
        guard let startedOn else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: startedOn)
        let logged = calendar.startOfDay(for: loggedOn)
        guard let days = calendar.dateComponents([.day], from: start, to: logged).day, days >= 0 else { return nil }
        return days / 7 + 1
    }

    /// The user's current fit answer for one item, as a set (GLO-67). The
    /// read half of `captureFit` — without it the control cannot show its
    /// saved state, only overwrite it.
    public func fits(itemID: UUID) async throws(GlossedError) -> Set<Fit> {
        _ = try await client.requireUserID()
        let rows: [FitOnlyRow] = try await run {
            try await client.supabase
                .from("item_fits")
                .select("fit")
                .eq("user_item_id", value: itemID.uuidString)
                .execute()
                .value
        }
        return Set(rows.map(\.fit))
    }

    /// Fit is captured at log time, on every log of an anchor-category product —
    /// most people log in five seconds and never rank (PRD §05).
    ///
    /// A *set*, because fit is multi-axis (GLO-67): lightness and undertone are
    /// independent, and a shade can miss on both. One RPC rather than upserts
    /// because the rules are about the set — `just right` is exclusive, one
    /// answer per axis, and a re-capture replaces the answer wholesale so
    /// cleared axes actually clear. The database enforces all three; this side
    /// does not re-derive them.
    public func captureFit(itemID: UUID, fits: Set<Fit>, season: String? = nil) async throws(GlossedError) {
        _ = try await client.requireUserID()
        let params = CaptureFitParams(
            userItemID: itemID.uuidString,
            // Sorted for a deterministic wire order — a Set would otherwise
            // make identical captures encode differently between runs.
            fits: fits.map(\.rawValue).sorted(),
            season: season
        )
        try await run {
            _ = try await client.supabase
                .rpc("capture_fit", params: params)
                .execute()
        }
    }

    /// Moves an item through its lifecycle — `want_to_try`, `own`, `finished`,
    /// `repurchased`. The write is row-scoped by RLS like every call here; a
    /// removed item's `rank_positions` row is deliberately untouched — it is
    /// hidden immediately and compacted at the ranking service's next rewrite
    /// of the category, never by a client-side write (GLO-72's decision).
    public func updateStatus(itemID: UUID, to status: ItemStatus) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("user_items")
                .update(["status": status.rawValue])
                .eq("id", value: itemID.uuidString)
                .execute()
        }
    }

    /// Soft delete — a shelf entry other rows point at is never hard-deleted.
    public func remove(itemID: UUID) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("user_items")
                .update(["deleted_at": Date().ISO8601Format()])
                .eq("id", value: itemID.uuidString)
                .execute()
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

public struct LogDraft: Sendable {
    public let variantID: UUID
    public let status: ItemStatus
    public let startedOn: Date?
    public let note: String?
    /// Client-generated so a retry resolves to the same row.
    public let clientID: UUID

    public init(
        variantID: UUID,
        status: ItemStatus = .own,
        startedOn: Date? = nil,
        note: String? = nil,
        clientID: UUID = UUID()
    ) {
        self.variantID = variantID
        self.status = status
        self.startedOn = startedOn
        self.note = note
        self.clientID = clientID
    }

    func row(userID: UUID) -> LogRow {
        LogRow(
            userID: userID.uuidString,
            variantID: variantID.uuidString,
            status: status.rawValue,
            startedOn: startedOn.map { $0.formatted(.iso8601.year().month().day()) },
            note: note,
            clientID: clientID.uuidString
        )
    }
}

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
