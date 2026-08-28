import DataKit
import Foundation

/// What the search rung needs from the catalog, and nothing more. DataKit is
/// frozen, so the conformance lives here — and naming only the two calls the
/// rung makes keeps a test double honest about what it stands in for.
public protocol CatalogSearching: Sendable {
    func search(_ query: String, limit: Int) async throws(GlossedError) -> [CatalogHit]
    func recordFailedSearch(_ query: String, domain: Domain?) async
}

extension CatalogRepository: CatalogSearching {}

/// Rung 1: type-ahead over the catalog, plus the bookkeeping a miss owes us.
public struct SearchRung: Sendable {
    /// Below this the user is still typing, not searching. A one-character
    /// query is not a miss and must never be recorded as demand.
    public static let minimumQueryLength = 2
    public static let resultLimit = 20

    public struct Result: Equatable, Sendable {
        public let hits: [CatalogHit]
        /// True when this empty result was recorded as demand. Every empty
        /// search names exactly which product is missing (tech/01 §4) — the
        /// highest-value catalog signal we will ever have, so a real miss is
        /// never silent.
        public let recordedMiss: Bool

        public var isEmpty: Bool {
            hits.isEmpty
        }
    }

    private let catalog: any CatalogSearching

    public init(catalog: any CatalogSearching) {
        self.catalog = catalog
    }

    /// Search as the user types.
    ///
    /// Personal-scope products belong to whoever created them, and RLS is what
    /// enforces that — this never filters by scope, so it cannot drift from the
    /// policy that actually decides.
    public func typeahead(
        _ raw: String,
        domain: Domain? = nil
    ) async throws(GlossedError) -> Result {
        let query = Ladder.tidy(raw)
        guard query.count >= SearchRung.minimumQueryLength else {
            return Result(hits: [], recordedMiss: false)
        }

        let hits = try await catalog.search(query, limit: SearchRung.resultLimit)
        guard hits.isEmpty else {
            return Result(hits: hits, recordedMiss: false)
        }

        await catalog.recordFailedSearch(query, domain: domain)
        return Result(hits: [], recordedMiss: true)
    }
}
