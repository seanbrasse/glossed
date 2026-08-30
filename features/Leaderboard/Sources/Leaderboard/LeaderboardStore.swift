import DataKit
import Foundation

/// How the board reaches its reads — the seam shape every feature uses.
public struct LeaderboardStore: Sendable {
    /// Rows arrive with claims ALREADY GATED (0042): `meanPercentile` nil
    /// below the face-off minimum. `scope` is "all" or "yours"; "yours"
    /// resolves the caller's cohort server-side.
    public var rows: @Sendable (_ categoryID: UUID, _ scope: String, _ ascending: Bool) async throws -> [LeaderboardRow]
    /// The category pills — same-domain siblings of wherever the board was
    /// opened from.
    public var categories: @Sendable (_ domain: Domain) async throws -> [DataKit.Category]

    public init(
        rows: @escaping @Sendable (UUID, String, Bool) async throws -> [LeaderboardRow],
        categories: @escaping @Sendable (Domain) async throws -> [DataKit.Category]
    ) {
        self.rows = rows
        self.categories = categories
    }

    public static func repository(
        aggregates: AggregatesRepository,
        catalog: CatalogRepository
    ) -> LeaderboardStore {
        LeaderboardStore(
            rows: { try await aggregates.leaderboard(categoryID: $0, scope: $1, ascending: $2) },
            categories: { try await catalog.categories(domain: $0) }
        )
    }
}
