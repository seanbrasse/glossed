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
    /// Below this the user is still typing, not searching, and a query that
    /// short must never be recorded as demand.
    ///
    /// It must match `CatalogRepository.search`'s own floor, which silently
    /// returns nothing below it: raise DataKit's and not this one, and queries
    /// in the gap get recorded as demand nobody expressed. DataKit is frozen,
    /// so the constant cannot be shared today — GLO-55 moves it there.
    public static let minimumQueryLength = 2

    /// Passed explicitly rather than leaning on the repository's default.
    public static let resultLimit = 20

    public struct Result: Equatable, Sendable {
        public let hits: [CatalogHit]
        /// A real query that came back empty — the highest-value catalog
        /// signal we get (tech/01 §4), so we report it as demand.
        ///
        /// It says the miss happened, not that it was persisted:
        /// `recordFailedSearch` swallows transport errors by design, so a
        /// dropped signal never blocks someone from adding a product. Nothing
        /// here can tell the difference, and claiming otherwise is the more
        /// expensive lie.
        public let isMiss: Bool

        /// Distinct from `isMiss`: a query too short to search is empty
        /// without being evidence of anything.
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
            return Result(hits: [], isMiss: false)
        }

        let hits = try await catalog.search(query, limit: SearchRung.resultLimit)
        guard hits.isEmpty else {
            return Result(hits: hits, isMiss: false)
        }

        await catalog.recordFailedSearch(query, domain: domain)
        return Result(hits: [], isMiss: true)
    }
}
