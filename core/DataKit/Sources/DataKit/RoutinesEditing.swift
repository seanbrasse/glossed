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
