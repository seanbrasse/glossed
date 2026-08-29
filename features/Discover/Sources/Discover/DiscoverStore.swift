import DataKit
import Foundation

/// How discover reaches its reads — the `ShelfChipStore` seam shape, for the
/// same reasons: the model tests against a recording stub, previews run with
/// no store, and live wiring is one line per side.
public struct DiscoverStore: Sendable {
    /// Stage 0/1 picks plus the daily wander (0040), best-first. Empty is a
    /// legitimate answer; the view owes the never-blank state, not the RPC.
    public var feed: @Sendable (_ limit: Int) async throws -> [DiscoverHit]
    /// The crosswalk card's rows — co-worn partners with their n.
    public var crosswalk: @Sendable (_ limit: Int) async throws -> [CrosswalkHit]

    public init(
        feed: @escaping @Sendable (Int) async throws -> [DiscoverHit],
        crosswalk: @escaping @Sendable (Int) async throws -> [CrosswalkHit]
    ) {
        self.feed = feed
        self.crosswalk = crosswalk
    }

    /// The live path — both reads come off the aggregates repository.
    public static func repository(_ aggregates: AggregatesRepository) -> DiscoverStore {
        DiscoverStore(
            feed: { try await aggregates.discoverFeed(limit: $0) },
            crosswalk: { try await aggregates.crosswalk(limit: $0) }
        )
    }
}
