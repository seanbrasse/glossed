import Foundation

// The discover read path's wire types (0040) and the taste vector's (0035).
// Their own file for the same dull reason as `Chips.swift`: `Models.swift`
// sits at the file-length ceiling, and these are ordinary domain models.

/// One discover row: a catalog hit plus why it is here. `discover_for_user`
/// returns `search_catalog`'s exact column set with `(basis, basis_n)`
/// appended — one row shape, one decoder, the `NearMatch` precedent.
public struct DiscoverHit: Decodable, Sendable, Identifiable, Hashable {
    /// Why a row was picked — machine keys from 0040; the CLIENT owns the
    /// copy. Exhaustive on purpose: a new basis added server-side is a
    /// decode failure here, not a row silently rendered under the wrong
    /// words — the `ShelfChip` valence treatment, for the same reason.
    public enum Basis: String, Decodable, Sendable {
        /// Stage 1 — ranked by the caller's own affinity vector (0035).
        /// `basisN` is how many of THEIR signals back the pick; this is not
        /// a population claim and carries no min-n.
        case taste
        /// Stage 0 — top of the caller's anchor-shade cohort. `basisN` is
        /// face-offs in that cohort, already ≥ `min_n_faceoffs()`.
        case shade
        /// The all-users cohort, same threshold.
        case everyone
        /// Plain ownership counts, ≥ `min_n_chip_claims()`.
        case popular
        /// The labeled wander (tech/01 §8's explicit slot against the
        /// filter bubble). `basisN` is 0 — it claims no evidence, and the
        /// render must say it is a wander, never a recommendation.
        case exploration
    }

    public let hit: CatalogHit
    public let basis: Basis
    public let basisN: Int

    public var id: UUID {
        hit.id
    }

    enum CodingKeys: String, CodingKey {
        case basis
        case basisN = "basis_n"
    }

    public init(from decoder: Decoder) throws {
        hit = try CatalogHit(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basis = try container.decode(Basis.self, forKey: .basis)
        basisN = try container.decode(Int.self, forKey: .basisN)
    }
}

/// One crosswalk partner: "people who wear <anchorLabel> also wear <hit>",
/// n people. The RPC thresholds n at `min_n_chip_claims()`; the render
/// always shows it and never says "your match" — the §05 copy rule.
public struct CrosswalkHit: Decodable, Sendable, Identifiable, Hashable {
    public let anchorVariantID: UUID
    /// Server-composed: brand + shade line of the caller's own anchor.
    public let anchorLabel: String
    public let hit: CatalogHit
    /// How many people wear both. Always rendered.
    public let n: Int

    public var id: UUID {
        hit.id
    }

    enum CodingKeys: String, CodingKey {
        case n
        case anchorVariantID = "anchor_variant_id"
        case anchorLabel = "anchor_label"
    }

    public init(from decoder: Decoder) throws {
        hit = try CatalogHit(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        anchorVariantID = try container.decode(UUID.self, forKey: .anchorVariantID)
        anchorLabel = try container.decode(String.self, forKey: .anchorLabel)
        n = try container.decode(Int.self, forKey: .n)
    }
}

/// One row of the caller's taste vector (`affinity_for_user`, 0035): an
/// attribute, the evidence behind it, and the confidence. `w` is the
/// ConfidenceMeter's number and the receipts gate (tech/01 §8) — a receipt
/// renders only when `w` says the vector has enough behind it to speak.
public struct AffinityRow: Decodable, Sendable, Identifiable, Hashable {
    public let attributeChipID: UUID
    public let label: String
    public let rawScore: Double
    /// How many of the caller's own logs back this dimension — the receipt's
    /// n ("from 3 of your logs"), never a population count.
    public let nSignals: Int
    /// `n/(n+10)` — the shrinkage weight and the confidence meter, one
    /// number. The wire column is `w` (0035); the name here says what it is.
    public let confidence: Double
    public let shrunkScore: Double

    public var id: UUID {
        attributeChipID
    }

    enum CodingKeys: String, CodingKey {
        case label
        case confidence = "w"
        case attributeChipID = "attribute_chip_id"
        case rawScore = "raw_score"
        case nSignals = "n_signals"
        case shrunkScore = "shrunk_score"
    }
}

/// One leaderboard row (0042): a catalog hit plus the board's numbers. The
/// claim arrives ALREADY GATED — `meanPercentile` is nil below the face-off
/// minimum, nulled by the RPC so no client can accidentally rank what the
/// evidence cannot. `needed` travels with the row ("k of 5" needs no client
/// constant), and `dislikeReasons` is non-nil only on the lowest board,
/// where the question is why.
public struct LeaderboardRow: Decodable, Sendable, Identifiable, Hashable {
    public let hit: CatalogHit
    /// Nil means "not enough face-offs yet", never "zero score".
    public let meanPercentile: Double?
    public let nUsers: Int
    public let needed: Int
    public let dislikeReasons: [String]?

    public var id: UUID {
        hit.id
    }

    /// The render rule's discriminator: a row below min-n shows "—" and the
    /// not-enough line instead of a rank.
    public var isRankable: Bool {
        meanPercentile != nil
    }

    enum CodingKeys: String, CodingKey {
        case meanPercentile = "mean_percentile"
        case nUsers = "n_users"
        case needed
        case dislikeReasons = "dislike_reasons"
    }

    public init(from decoder: Decoder) throws {
        hit = try CatalogHit(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meanPercentile = try container.decodeIfPresent(Double.self, forKey: .meanPercentile)
        nUsers = try container.decode(Int.self, forKey: .nUsers)
        needed = try container.decode(Int.self, forKey: .needed)
        dislikeReasons = try container.decodeIfPresent([String].self, forKey: .dislikeReasons)
    }
}
