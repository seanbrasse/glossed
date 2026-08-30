import Foundation
import Supabase

/// Reads the anonymous aggregates. Everything here goes through a database
/// function: the aggregate tables carry no user policies at all, so there is no
/// path to raw rows and no way to render a claim below its minimum sample.
public struct AggregatesRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    /// Onboarding's payoff. Callable before an account exists, because the
    /// payoff comes before signup.
    ///
    /// The caller must respect `evidenceBacked`: when it is false there is no
    /// claim to make, and the screen shows the neutral fallback instead. One
    /// weak early recommendation poisons every good one after it.
    public func payoff(variantID: UUID) async throws(GlossedError) -> PayoffEvidence {
        let rows: [PayoffEvidence] = try await run {
            try await client.supabase
                .rpc("payoff_for_variant", params: ["p_variant_id": variantID.uuidString])
                .execute()
                .value
        }
        guard let evidence = rows.first else {
            return PayoffEvidence(exactShadeCount: 0, withFitCount: 0, evidenceBacked: false)
        }
        return evidence
    }

    /// The discover feed (0040): Stage 0/1 picks plus the daily wander, one
    /// call. Rows arrive best-first; the basis explains each and the client
    /// owns the words. Empty is a legitimate answer — the screen's
    /// never-blank obligation is met with its own state, not fabricated rows.
    public func discoverFeed(limit: Int = 12) async throws(GlossedError) -> [DiscoverHit] {
        try await run {
            try await client.supabase
                .rpc("discover_for_user", params: ["p_limit": limit])
                .execute()
                .value
        }
    }

    /// The crosswalk card's rows (0040): partners co-worn with the caller's
    /// anchors, n always present, thresholded server-side.
    public func crosswalk(limit: Int = 6) async throws(GlossedError) -> [CrosswalkHit] {
        try await run {
            try await client.supabase
                .rpc("crosswalk_for_user", params: ["p_limit": limit])
                .execute()
                .value
        }
    }

    /// The caller's taste vector (0035), computed on read and stored nowhere
    /// — domain.md §5 classifies inferred taste with stated data, so the
    /// vector exists only at query time and inherits deletion semantics from
    /// the rows it reads.
    public func affinity() async throws(GlossedError) -> [AffinityRow] {
        try await run {
            try await client.supabase
                .rpc("affinity_for_user")
                .execute()
                .value
        }
    }

    /// The board (0042). `scope` is "all" or "yours" — "yours" resolves the
    /// caller's cohort server-side, so no cohort key is ever built here.
    /// Ascending is the lowest board, and only it carries reasons.
    public func leaderboard(
        categoryID: UUID,
        scope: String = "all",
        ascending: Bool = false,
        limit: Int = 25
    ) async throws(GlossedError) -> [LeaderboardRow] {
        struct Params: Encodable {
            let pCategory: String
            let pScope: String
            let pAscending: Bool
            let pLimit: Int

            enum CodingKeys: String, CodingKey {
                case pCategory = "p_category"
                case pScope = "p_scope"
                case pAscending = "p_ascending"
                case pLimit = "p_limit"
            }
        }
        return try await run {
            try await client.supabase
                .rpc("leaderboard", params: Params(
                    pCategory: categoryID.uuidString, pScope: scope,
                    pAscending: ascending, pLimit: limit
                ))
                .execute()
                .value
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
