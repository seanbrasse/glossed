import Foundation
import Supabase

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

    /// Someone else's routine, in order.
    ///
    /// Three scoped reads rather than one RPC: `routines_public` and
    /// `routine_steps_public` gate on `can_view(owner, 'routines')`, and the
    /// step products come through `user_shelf_items`, which is
    /// `security_invoker` and so inherits `user_items_public`. That policy
    /// admits an item via `item_is_published` when it sits in a routine the
    /// viewer may see — which is why a private shelf still renders its
    /// routine's products, and why nothing here needs a shelf scope.
    ///
    /// Returns nil when the routine is not visible; the caller must not
    /// distinguish that from "no such routine".
    public func routineDetail(routineID: UUID) async throws(GlossedError) -> RoutineDetail? {
        let routines: [RoutineRow] = try await run {
            try await client.supabase
                .from("routines")
                .select("id,title,slot,started_on")
                .eq("id", value: routineID.uuidString)
                .execute()
                .value
        }
        guard let routine = routines.first else { return nil }

        let steps: [StepRow] = try await run {
            try await client.supabase
                .from("routine_steps")
                .select("position,user_item_id")
                .eq("routine_id", value: routineID.uuidString)
                .order("position")
                .execute()
                .value
        }
        guard !steps.isEmpty else {
            return RoutineDetail(
                routineID: routine.id, title: routine.title, slot: routine.slot,
                startedOn: PostgresDay.parse(routine.startedOnRaw), steps: []
            )
        }

        let items: [ShelfNameRow] = try await run {
            try await client.supabase
                .from("user_shelf_items")
                .select("user_item_id,brand_name,product_name,variant_label")
                .in("user_item_id", values: steps.map(\.userItemID.uuidString))
                .execute()
                .value
        }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.userItemID, $0) })

        // A step whose product the viewer cannot read is dropped, not rendered
        // blank: a numbered gap invites the question of what is hidden.
        let named = steps.compactMap { step -> RoutineStep? in
            guard let item = byID[step.userItemID] else { return nil }
            return RoutineStep(
                position: step.position, userItemID: step.userItemID,
                brandName: item.brandName, productName: item.productName,
                variantLabel: item.variantLabel
            )
        }
        return RoutineDetail(
            routineID: routine.id, title: routine.title, slot: routine.slot,
            startedOn: PostgresDay.parse(routine.startedOnRaw), steps: named
        )
    }

    private struct RoutineRow: Decodable {
        let id: UUID
        let title: String
        let slot: RoutineSlot
        let startedOnRaw: String?

        enum CodingKeys: String, CodingKey {
            case id, title, slot
            case startedOnRaw = "started_on"
        }
    }

    private struct StepRow: Decodable {
        let position: Int
        let userItemID: UUID

        enum CodingKeys: String, CodingKey {
            case position
            case userItemID = "user_item_id"
        }
    }

    private struct ShelfNameRow: Decodable {
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

    private func run<T>(_ work: () async throws -> T) async throws(GlossedError) -> T {
        do {
            return try await work()
        } catch {
            throw GlossedError.from(error)
        }
    }
}
