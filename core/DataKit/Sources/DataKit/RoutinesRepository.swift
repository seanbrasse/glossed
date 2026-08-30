import Foundation
import Supabase

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

    /// Your own routines, newest first, each with its steps in order.
    ///
    /// The read half of `saveDraft`, and the one GLO-230 was blocked on:
    /// `BrowseRepository.routines` answers "other people's", excluding on
    /// scope, `discoverable`, an unapproved title and blocks — so it can never
    /// return yours, and should not. This one is scoped by `routines_own` to
    /// `auth.uid()` and asks nothing about visibility, because the owner's own
    /// list is not a public surface.
    ///
    /// Three reads rather than one RPC, matching `routineDetail`: the step
    /// products come through `user_shelf_items`, which is `security_invoker`
    /// and so inherits the shelf policies rather than re-implementing them.
    ///
    /// Soft-deleted routines are excluded — `deleted_at` is the schema's
    /// intent, and `remove` below honours it.
    public func mine() async throws(GlossedError) -> [MyRoutine] {
        _ = try await client.requireUserID()
        let routines: [OwnRoutineRow] = try await run {
            try await client.supabase
                .from("routines")
                .select("id,title,slot,started_on,created_at")
                .is("deleted_at", value: nil)
                .order("created_at", ascending: false)
                .execute()
                .value
        }
        guard !routines.isEmpty else { return [] }

        let steps: [OwnStepRow] = try await run {
            try await client.supabase
                .from("routine_steps")
                .select("routine_id,position,user_item_id")
                .in("routine_id", values: routines.map(\.id.uuidString))
                .order("position")
                .execute()
                .value
        }
        let names = try await stepNames(for: steps)
        return RoutinesRepository.assemble(routines: routines, steps: steps, names: names)
    }

    /// Renames a routine. **This is half of a rename, and the other half is
    /// not here.**
    ///
    /// `routines.title` is the owner's copy — the only one this call touches,
    /// and the only one the profile's own tabs render. The title a stranger
    /// sees in browse is a separate `public_texts` row (`routine_title`,
    /// `subject_id` = the routine), which `browse_routines` INNER JOINs on
    /// `state = 'approved'`. A caller that wants the new name to reach browse
    /// must also call `SafetyRepository.submitPublicText(kind: .routineTitle,
    /// subjectID:body:)`.
    ///
    /// Kept apart rather than fused because `ProfileRepository` keeps the bio
    /// and its public text apart for the same reason: one write per table, and
    /// a moderation record is never a side effect of a column update.
    ///
    /// An all-whitespace title is rejected rather than stored — a routine with
    /// a blank name is unaddressable in a list, and the column is `not null`
    /// but not `check (length > 0)`.
    public func rename(routineID: UUID, to title: String) async throws(GlossedError) {
        _ = try await client.requireUserID()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GlossedError(
                .invalidInput,
                userMessage: "give it a name.",
                debugDetail: "blank routine title"
            )
        }
        try await run {
            _ = try await client.supabase
                .from("routines")
                .update(TitleUpdate(title: trimmed, updatedAt: Date().ISO8601Format()))
                .eq("id", value: routineID.uuidString)
                .execute()
        }
    }

    /// Soft delete. `deleted_at` exists on `routines` and both public
    /// predicates already test it (`routines_public`, `routine_steps_public`),
    /// so setting it is what actually retracts the routine — a hard delete
    /// would cascade `routine_steps` away and lose the fact that the routine
    /// was ever run, which the shelf's own `remove` deliberately preserves.
    public func remove(routineID: UUID) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("routines")
                .update(["deleted_at": Date().ISO8601Format()])
                .eq("id", value: routineID.uuidString)
                .execute()
        }
    }

    private func stepNames(for steps: [OwnStepRow]) async throws(GlossedError) -> [ShelfNameRow] {
        guard !steps.isEmpty else { return [] }
        return try await run {
            try await client.supabase
                .from("user_shelf_items")
                .select("user_item_id,brand_name,product_name,variant_label")
                .in("user_item_id", values: steps.map(\.userItemID.uuidString))
                .execute()
                .value
        }
    }

    /// Pure assembly, so the ordering rule is testable without a database.
    ///
    /// **Steps are sorted here even though the query already ordered them.**
    /// PostgREST's `order` is a request, not a guarantee the decoder preserves
    /// across a grouped rebuild, and `routine_steps`' primary key is
    /// `(routine_id, user_item_id)` — nothing about the storage order is
    /// positional. A routine rendered out of order is silently wrong rather
    /// than visibly broken, which is the failure worth spending a sort on.
    ///
    /// A step whose product the caller cannot read is DROPPED, not rendered
    /// blank — the same choice `routineDetail` makes, for the same reason: a
    /// numbered gap invites the question of what is hidden.
    static func assemble(
        routines: [OwnRoutineRow], steps: [OwnStepRow], names: [ShelfNameRow]
    ) -> [MyRoutine] {
        let byItem = Dictionary(names.map { ($0.userItemID, $0) }, uniquingKeysWith: { first, _ in first })
        let byRoutine = Dictionary(grouping: steps, by: \.routineID)
        return routines.map { routine in
            let named = (byRoutine[routine.id] ?? [])
                .sorted { $0.position < $1.position }
                .compactMap { step -> RoutineStep? in
                    guard let item = byItem[step.userItemID] else { return nil }
                    return RoutineStep(
                        position: step.position, userItemID: step.userItemID,
                        brandName: item.brandName, productName: item.productName,
                        variantLabel: item.variantLabel
                    )
                }
            return MyRoutine(
                routineID: routine.id, title: routine.title, slot: routine.slot,
                startedOn: PostgresDay.parse(routine.startedOnRaw),
                createdAt: routine.createdAt, steps: named
            )
        }
    }

    struct OwnRoutineRow: Decodable {
        let id: UUID
        let title: String
        let slot: RoutineSlot
        let startedOnRaw: String?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title, slot
            case startedOnRaw = "started_on"
            case createdAt = "created_at"
        }
    }

    struct OwnStepRow: Decodable {
        let routineID: UUID
        let position: Int
        let userItemID: UUID

        enum CodingKeys: String, CodingKey {
            case routineID = "routine_id"
            case position
            case userItemID = "user_item_id"
        }
    }

    /// `title` and `updated_at` together: `routines` carries no touch trigger
    /// (probed — `pg_trigger` is empty for it), so a rename that did not set
    /// `updated_at` would leave the row claiming it was last changed at
    /// creation.
    struct TitleUpdate: Encodable {
        let title: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case title
            case updatedAt = "updated_at"
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
