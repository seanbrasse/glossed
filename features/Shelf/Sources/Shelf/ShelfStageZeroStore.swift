import DataKit
import Foundation

/// The three picks a cold-start shelf opens with. GLO-211.
///
/// `G.Shelf`'s empty branch is not the one-line dead end the other four blank
/// states are — it is the product's opening argument: *we already know your
/// shade, here are three things people who share it kept.* Its own footer
/// states the rule: "empty states are never blank".
///
/// Same seam as `ShelfChipStore` and `ShelfFitStore`, for the same reasons:
/// the model tests against a stub, fixture states run with no store at all,
/// and live wiring is one line.
public struct ShelfStageZeroStore: Sendable {
    public var picks: @Sendable (_ limit: Int) async throws -> [StageZeroPick]

    public init(picks: @escaping @Sendable (_ limit: Int) async throws -> [StageZeroPick]) {
        self.picks = picks
    }

    /// The live one. A feature cannot import a feature, so the shelf reaches
    /// `AggregatesRepository` directly rather than through `features/Discover`
    /// — `features → core` is the allowed direction.
    public static func repository(_ aggregates: AggregatesRepository) -> ShelfStageZeroStore {
        ShelfStageZeroStore { limit in
            let hits = try await aggregates.discoverFeed(limit: limit)
            return hits.compactMap(StageZeroPick.init(hit:))
        }
    }
}

/// One recommended product on the cold-start shelf, with the sentence that
/// says why it is there.
public struct StageZeroPick: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let brand: String
    public let name: String
    /// The n behind the claim, and the claim itself. Never rendered without
    /// each other — every claim in UI copy carries its n.
    public let n: Int
    public let reason: String
    /// Kept, not discarded after building `reason`: a `.shade` pick is
    /// evidence the server matched this person to an anchor cohort, which is
    /// the only thing the shelf can honestly say about how many anchors they
    /// hold. See `ShelfStageZeroView.anchorsHeld`.
    public let basis: DiscoverHit.Basis

    public init(id: UUID, brand: String, name: String, n: Int, reason: String, basis: DiscoverHit.Basis) {
        self.id = id
        self.brand = brand
        self.name = name
        self.n = n
        self.reason = reason
        self.basis = basis
    }
}

public extension StageZeroPick {
    /// Built from a discover row, or nil when the row cannot carry a claim.
    ///
    /// **`.exploration` is dropped here, deliberately.** Its `basisN` is 0 by
    /// construction — it is the labelled wander against the filter bubble
    /// (tech/01 §8) and claims no evidence. On a screen whose entire job is
    /// "here is why we think you'll keep this", a row that cannot say why is
    /// worse than three rows instead of four.
    init?(hit: DiscoverHit) {
        guard hit.basis != .exploration, hit.basisN > 0 else { return nil }
        self.init(
            id: hit.hit.id,
            brand: hit.hit.brandName,
            name: hit.hit.name,
            n: hit.basisN,
            reason: Self.reason(for: hit.basis),
            basis: hit.basis
        )
    }

    /// The client owns this copy — `DiscoverHit.Basis` is machine keys from
    /// 0040 and says so. Phrased as a cohort by kind, never by value: "your
    /// shade", not the shade itself (GLO-205's rule, and GLO-167's before it).
    static func reason(for basis: DiscoverHit.Basis) -> String {
        switch basis {
        case .shade: "people in your shade kept it"
        case .taste: "matches what you've liked"
        case .everyone: "kept across everyone"
        case .popular: "own it"
        case .exploration: "a wander"
        }
    }
}
