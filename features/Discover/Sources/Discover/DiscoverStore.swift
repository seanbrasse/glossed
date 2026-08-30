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
    /// "Not for me" (GLO-181): writes the domain row the engine reads. Nil
    /// in previews and fixtures, and the UI hides the gesture then — an
    /// editor that writes nowhere must not be offered (the chips rule).
    public var dismiss: (@Sendable (_ productID: UUID, _ reason: String?) async throws -> Void)?

    public init(
        feed: @escaping @Sendable (Int) async throws -> [DiscoverHit],
        crosswalk: @escaping @Sendable (Int) async throws -> [CrosswalkHit],
        dismiss: (@Sendable (UUID, String?) async throws -> Void)? = nil
    ) {
        self.feed = feed
        self.crosswalk = crosswalk
        self.dismiss = dismiss
    }

    /// The live path — reads off the aggregates repository, the write off
    /// the taste repository (the registry's two sides).
    public static func repository(_ aggregates: AggregatesRepository, taste: TasteRepository) -> DiscoverStore {
        DiscoverStore(
            feed: { try await aggregates.discoverFeed(limit: $0) },
            crosswalk: { try await aggregates.crosswalk(limit: $0) },
            dismiss: { try await taste.dismissRecommendation(productID: $0, reason: $1) }
        )
    }
}
