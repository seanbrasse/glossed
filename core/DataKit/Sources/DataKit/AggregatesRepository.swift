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

    private func run<T>(_ work: () async throws -> T) async throws(GlossedError) -> T {
        do {
            return try await work()
        } catch {
            throw GlossedError.from(error)
        }
    }
}
