import Foundation
import Supabase

// The routine's after-the-fact scope write (0053, GLO-272). Split from
// `RoutinesRepository.swift` for the 300-line ceiling, the same split
// `LooksEditing.swift` is.

extension RoutinesRepository {
    /// Who may read this routine (0053) — the archive control's write.
    /// Ships `updated_at` by hand for the same reason `rename` does: no
    /// touch trigger on `routines`.
    public func setVisibility(routineID: UUID, to scope: PrivacyScope) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("routines")
                .update(ScopeUpdate(visibility: scope, updatedAt: Date().ISO8601Format()))
                .eq("id", value: routineID.uuidString)
                .execute()
        }
    }

    /// The edit path `saveDraft` says it is not: SET semantics for a
    /// routine's steps. Upsert re-positions the steps it is given and cannot
    /// know about one that was REMOVED (saveDraft's own comment), so an edit
    /// deletes the set and re-lands the new one.
    ///
    /// Not atomic across the two statements: a failure between them leaves
    /// the routine bare, and the caller's retry with the SAME steps re-lands
    /// them — `(routine_id, user_item_id)` keys, so the retry cannot
    /// duplicate. The delete is pinned to the one routine id the caller
    /// already owns (GLO-258's rule).
    public func replaceSteps(
        routineID: UUID, with steps: [RoutineDraft.Step]
    ) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("routine_steps")
                .delete()
                .eq("routine_id", value: routineID.uuidString)
                .execute()
            guard !steps.isEmpty else { return }
            let rows = steps.enumerated().map { index, step in
                let trimmed = step.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                return StepRow(
                    routineID: routineID, userItemID: step.userItemID, position: index,
                    note: (trimmed?.isEmpty ?? true) ? nil : trimmed
                )
            }
            try await client.supabase
                .from("routine_steps")
                .insert(rows)
                .execute()
        }
    }

    /// One write, exactly its columns — the `StateUpdate` discipline.
    struct ScopeUpdate: Encodable {
        let visibility: PrivacyScope
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case visibility
            case updatedAt = "updated_at"
        }
    }
}
