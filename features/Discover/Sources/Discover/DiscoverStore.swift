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
    /// Every category, for the frame's per-cell eyebrow (GLO-226). Set after
    /// construction rather than through `init` so the initialiser stays inside
    /// the parameter-count limit — the config's own "prefer an options struct"
    /// note, answered with the cheaper shape a struct of closures already has.
    ///
    /// Nil renders NO eyebrow, and that is the point: `categorySlug` is on the
    /// wire but the human label is not, and three of the catalog's twenty-two
    /// slugs differ from their label (`eye` → "eye care", `serum` → "serums +
    /// actives", `styler` → "stylers"). A client that de-hyphenated the slug
    /// would be inventing catalog copy for those three, so the label is read
    /// or it is not shown.
    public var categories: (@Sendable () async throws -> [DataKit.Category])?

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
    ///
    /// `catalog` is optional because the app's existing call site does not
    /// pass one yet: without it the picks render exactly as they do today,
    /// with it they gain the frame's category eyebrow. One argument, no
    /// behaviour change for anything else.
    public static func repository(
        _ aggregates: AggregatesRepository,
        taste: TasteRepository,
        catalog: CatalogRepository? = nil
    ) -> DiscoverStore {
        var store = DiscoverStore(
            feed: { try await aggregates.discoverFeed(limit: $0) },
            crosswalk: { try await aggregates.crosswalk(limit: $0) },
            dismiss: { try await taste.dismissRecommendation(productID: $0, reason: $1) }
        )
        // One call for every domain, not one per domain: a stream mixes
        // makeup with skincare, and `categories(domain:)` already takes nil
        // to mean all of them (the add-ladder's create rung does the same).
        if let catalog {
            store.categories = { try await catalog.categories(domain: nil) }
        }
        return store
    }
}
