import Foundation
import Supabase

// `RoutineSlot` is NOT declared here — it already exists in `BrowseModels.swift`,
// mirroring `routine_slot` from `20260828000003_ranking.sql:4`. Redeclaring it
// is how this file was first written, and the compiler caught it; a second copy
// would have been a second place for the wire words to drift.

/// A routine as the composer hands it over, in one shape — the repository
/// writes parent and steps itself, so a caller cannot invent an ordering that
/// leaves a stepless routine behind on a mid-flight failure.
public struct RoutineDraft: Sendable {
    public let title: String
    public let slot: RoutineSlot
    /// `user_items.id`s, in the order they should run. A routine is a sequence
    /// of things you OWN — the schema says so, with `routine_steps.user_item_id`
    /// referencing `user_items`, never `products` or `variants`.
    public let stepItemIDs: [UUID]
    /// Idempotency, the LookDraft pattern: the caller mints the routine's
    /// PRIMARY KEY, so a retry after a failed save upserts the same row rather
    /// than minting a second routine with the same name.
    public let routineID: UUID

    public init(
        title: String,
        slot: RoutineSlot,
        stepItemIDs: [UUID],
        routineID: UUID = UUID()
    ) {
        self.title = title
        self.slot = slot
        self.stepItemIDs = stepItemIDs
        self.routineID = routineID
    }
}

/// Writes for routines (schema 0003). Session-scoped opening, Aug 30: granted
/// for exactly this repository.
///
/// **Privacy is not written here, because it is not a column.** `routines` has
/// no visibility field; who may read a routine is decided at SELECT time by
/// `can_view(user_id, 'routines')` against the owner's `privacy_scopes` row,
/// which fails closed when absent. Nothing this repository writes can widen or
/// narrow that — see GLO-208, filed because the composer's copy claims
/// otherwise.
public struct RoutinesRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    struct RoutineRow: Encodable {
        let id: UUID
        let userID: UUID
        let title: String
        let slot: RoutineSlot

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case title, slot
        }
    }

    struct StepRow: Encodable {
        let routineID: UUID
        let userItemID: UUID
        let position: Int

        enum CodingKeys: String, CodingKey {
            case routineID = "routine_id"
            case userItemID = "user_item_id"
            case position
        }
    }

    private struct InsertedID: Decodable {
        let id: UUID
    }

    /// Parent first, steps after, position taken from the array's own order.
    ///
    /// A mid-flight failure cannot duplicate: the caller still holds the draft,
    /// whose `routineID` is the primary key, so retrying the SAME draft upserts
    /// the same routine and re-lands the same steps — resume, not restart.
    /// `routine_steps`' primary key is `(routine_id, user_item_id)`, which is
    /// also why a product can appear in a routine only once; the composer's
    /// toggle already enforces that on the way in.
    ///
    /// **This is create, not edit.** Upsert re-positions the steps it is given
    /// and cannot know about one that was REMOVED, so re-saving a shortened
    /// draft under the same id would leave the dropped step behind. An edit
    /// path needs set semantics — delete-then-insert inside one RPC, so a
    /// failure between the two cannot stand a routine up with no steps.
    public func saveDraft(_ draft: RoutineDraft) async throws(GlossedError) -> UUID {
        let userID = try await client.requireUserID()
        let routineID: UUID = try await run {
            let inserted: InsertedID = try await client.supabase
                .from("routines")
                .upsert(
                    RoutineRow(
                        id: draft.routineID,
                        userID: userID,
                        title: draft.title,
                        slot: draft.slot
                    ),
                    onConflict: "id"
                )
                .select("id")
                .single()
                .execute()
                .value
            return inserted.id
        }
        try await run {
            guard !draft.stepItemIDs.isEmpty else { return }
            let rows = draft.stepItemIDs.enumerated().map { index, itemID in
                StepRow(routineID: routineID, userItemID: itemID, position: index)
            }
            try await client.supabase
                .from("routine_steps")
                .upsert(rows, onConflict: "routine_id,user_item_id")
                .execute()
        }
        return routineID
    }

    private func run<T>(_ work: () async throws -> T) async throws(GlossedError) -> T {
        do {
            return try await work()
        } catch {
            throw GlossedError.from(error)
        }
    }
}
