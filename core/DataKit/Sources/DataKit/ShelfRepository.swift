import Foundation
import Supabase

/// The user's own shelf: items, chips, fits.
///
/// **RLS is not what makes a read here "mine", and the comment that used to
/// stand in this place said it was.** `user_items` carries TWO select policies
/// — `user_items_own` and `user_items_public` — and Postgres OR's policies for
/// the same command, so an unfiltered select returns your own rows *plus* every
/// row `item_is_published()` admits. `user_shelf_items` is `security_invoker`
/// and inherits exactly that.
///
/// Probed, not reasoned: with juli's `privacy_scopes.shelf` set to `public`, as
/// maya `select … from user_shelf_items` returned six rows — maya's five and
/// juli's one. With `user_id = auth.uid()` pinned it returned five. Every
/// collection read below therefore pins `user_id` itself, and
/// `requireUserID()`'s return value is USED rather than discarded — discarding
/// it is the tell this defect leaves behind (GLO-258, and #387 for the same
/// defect in `RoutinesRepository.mine`).
public struct ShelfRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    public func items(status: ItemStatus? = nil) async throws(GlossedError) -> [UserItem] {
        let userID = try await client.requireUserID()
        return try await run {
            let base = client.supabase
                .from("user_items")
                .select()
                .eq("user_id", value: userID.uuidString)
                .is("deleted_at", value: nil)
            let filtered = status.map { base.eq("status", value: $0.rawValue) } ?? base
            return try await filtered.order("created_at", ascending: false).execute().value
        }
    }

    /// The shelf, as it is drawn: one read of `user_shelf_items`, which joins
    /// `user_items → variants → products → brands → categories` and carries the
    /// rank. `items(status:)` above returns the raw table rows — a variant id
    /// and a status — which is enough to count what you own and nothing else.
    ///
    /// `user_id` is pinned for the reason the type comment gives. The view is
    /// `security_invoker`, so it is `user_items`' OR'd policies answering here,
    /// and a shelf that quietly grew somebody else's foundation is what this
    /// predicate stops — on this screen and on the profile's shelf tab.
    public func shelf(status: ItemStatus? = nil) async throws(GlossedError) -> [ShelfRow] {
        let userID = try await client.requireUserID()
        return try await run {
            let base = client.supabase
                .from("user_shelf_items")
                .select()
                .eq("user_id", value: userID.uuidString)
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

    /// The chips the user has put on one item, with the vocabulary row embedded
    /// so the sheet renders labels without a second read. The read half of
    /// `applyChip` — without it the sheet can only add, never show what is
    /// already there.
    public func chips(itemID: UUID) async throws(GlossedError) -> [AppliedChip] {
        _ = try await client.requireUserID()
        return try await run {
            try await client.supabase
                .from("item_chips")
                .select("id, week, freetext, experience_chips(id, domain, category_id, slug, label, valence)")
                .eq("user_item_id", value: itemID.uuidString)
                .order("created_at")
                .execute()
                .value
        }
    }

    /// Takes a chip back off an item. A hard delete on purpose: unlike a shelf
    /// entry, nothing points at an `item_chips` row, and a soft-deleted chip
    /// would still occupy the `(user_item_id, experience_chip_id)` unique key —
    /// so re-applying a chip you removed would conflict instead of working.
    public func removeChip(itemID: UUID, chipID: UUID) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("item_chips")
                .delete()
                .eq("user_item_id", value: itemID.uuidString)
                .eq("experience_chip_id", value: chipID.uuidString)
                .execute()
        }
    }

    /// The item's free-text note. `nil` clears it, and clearing has to actually
    /// reach the database as a null — see `NoteUpdate` for why that needs an
    /// explicit encoder.
    public func updateNote(itemID: UUID, to note: String?) async throws(GlossedError) {
        _ = try await client.requireUserID()
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        // An all-whitespace note is a cleared note, not a note made of spaces.
        let normalized = (trimmed?.isEmpty ?? true) ? nil : trimmed
        try await run {
            _ = try await client.supabase
                .from("user_items")
                .update(NoteUpdate(note: normalized))
                .eq("id", value: itemID.uuidString)
                .execute()
        }
    }

    /// The item's pre-ranking like signal, or nil when it has never been set.
    ///
    /// Reads `user_items` directly rather than the shelf view: `like_state` is
    /// not among the view's columns, and appending it is a migration this call
    /// deliberately does not require. A missing row and a null column both come
    /// back nil — the sheet treats them the same way, as "no answer yet".
    public func likeState(itemID: UUID) async throws(GlossedError) -> LikeState? {
        _ = try await client.requireUserID()
        let rows: [LikeStateRow] = try await run {
            try await client.supabase
                .from("user_items")
                .select("like_state")
                .eq("id", value: itemID.uuidString)
                .execute()
                .value
        }
        return rows.first?.likeState
    }

    /// Sets the pre-ranking like signal. `nil` clears it back to no answer,
    /// which is a different fact from `.neutral` — one is "never asked", the
    /// other is "asked, and they shrugged".
    public func updateLikeState(itemID: UUID, to state: LikeState?) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("user_items")
                .update(LikeStateUpdate(likeState: state?.rawValue))
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
