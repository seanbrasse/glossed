import DataKit
import Foundation

/// Products the search rung offers before a letter is typed. Sean, Sep 2:
/// *"the add a product screen should have suggestions for the user to click
/// on without searching: … things we recommend them based off of the data we
/// have on their skin and people similar to them."*
///
/// A seam, like `CatalogSearching`: the model tests against a stub, fixtures
/// run with none, and the live one is `AggregatesRepository` — the discover
/// feed (0040), whose basis says why each row is here and whose `basisN` is
/// the n every claim carries. Things the person has *saved* are not here yet:
/// saves are a spec (tech/03 §1a) and want-to-try lives on the shelf already.
public protocol LadderSuggesting: Sendable {
    func suggestions(limit: Int) async throws -> [LadderSuggestion]
}

/// One suggested product and the sentence that earns its place.
public struct LadderSuggestion: Identifiable, Equatable, Sendable {
    public let hit: CatalogHit
    /// The n behind the claim, and the claim. Rendered together, always.
    public let n: Int
    public let reason: String

    public var id: UUID {
        hit.id
    }

    public init(hit: CatalogHit, n: Int, reason: String) {
        self.hit = hit
        self.n = n
        self.reason = reason
    }

    /// What the row prints — `EvidenceLine`'s own shape (`n label`) in one
    /// string, because the option row's reason slot is a string. A wander
    /// has no n and prints none: it claims nothing, and says so.
    public var line: String {
        n > 0 ? "\(n) \(reason)" : reason
    }
}

public extension LadderSuggestion {
    /// Built from a discover row. Every row is kept, including the wander.
    ///
    /// The shelf's `StageZeroPick` drops `.exploration` because its screen
    /// promises "here is why"; this list promises only a place to start, and
    /// the wander is labelled as one with no n, the way discover shows it.
    /// The difference matters on thin data: with three seeded accounts no
    /// cohort clears min-n, the feed is one wander, and a rule that dropped
    /// it left the rung bare — which is what Sean opened (Sep 2). Rows
    /// arrive best-first from 0040, so claims lead and wanders trail.
    init(hit: DiscoverHit) {
        self.init(hit: hit.hit, n: hit.basisN, reason: Self.reason(for: hit.basis))
    }

    /// The client owns this copy — `DiscoverHit.Basis` is machine keys from
    /// 0040. A cohort by kind, never by value: "your shade", not the shade.
    /// Twinned with the shelf's `StageZeroPick.reason(for:)`: a feature
    /// cannot import a feature.
    static func reason(for basis: DiscoverHit.Basis) -> String {
        switch basis {
        case .shade: "people in your shade kept it"
        case .taste: "matches what you've liked"
        case .everyone: "kept across everyone"
        case .popular: "own it"
        case .exploration: "a wander — no evidence, just curiosity"
        }
    }
}

extension AggregatesRepository: LadderSuggesting {
    public func suggestions(limit: Int) async throws -> [LadderSuggestion] {
        try await discoverFeed(limit: limit).map(LadderSuggestion.init(hit:))
    }
}
