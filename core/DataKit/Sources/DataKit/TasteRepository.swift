import Foundation
import Supabase

/// Writes for the taste engine's signal registry (tech/07 §2) — the rows a
/// user tells the engine directly, as opposed to what it infers from their
/// shelf. Its own repository because these are neither shelf rows nor
/// aggregate reads: they are the discover surface talking back.
///
/// Opened under Sean's Aug 29 per-session grant (the discover build-out).
public struct TasteRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    /// "Not for me" (GLO-181, 0041). One row per (user, product) — the
    /// upsert makes a second swipe idempotent rather than a louder signal,
    /// the same shape the unique constraint enforces server-side. The row is
    /// the user's own, deletable, and never mined from analytics — the
    /// rec_dismissed EVENT is emitted by the caller alongside this write;
    /// nothing reads it back (tech/07's boundary).
    public func dismissRecommendation(productID: UUID, reason: String?) async throws(GlossedError) {
        struct Row: Encodable {
            let userID: String
            let productID: String
            let reason: String?

            enum CodingKeys: String, CodingKey {
                case reason
                case userID = "user_id"
                case productID = "product_id"
            }
        }
        let userID = try await client.requireUserID()
        let row = Row(userID: userID.uuidString, productID: productID.uuidString, reason: reason)
        try await run {
            _ = try await client.supabase
                .from("rec_dismissals")
                .upsert(row, onConflict: "user_id,product_id")
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
