import Foundation

// The experience-chip vocabulary and the pre-ranking like signal. Split out of
// `Models.swift` only because that file hit the 300-line ceiling; these are
// ordinary domain models and belong beside the rest.

/// Whether a chip is a good thing or a bad thing to say about a product —
/// `chip_valence` in 0001. The two aggregate in opposite directions, so this
/// is a fact about the vocabulary, never a per-user opinion.
public enum ChipValence: String, Codable, Sendable, CaseIterable {
    case like, dislike
}

/// One entry in the experience-chip vocabulary — the canonical list a user
/// picks from, not anything they have said yet. `categoryID` is nil for chips
/// that apply to a whole domain; a non-nil one narrows the chip to a single
/// category (PRD §03 splits attribute chips from experience chips, and the
/// experience half is what this table holds).
public struct ExperienceChip: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let domain: Domain
    public let categoryID: UUID?
    public let slug: String
    public let label: String
    public let valence: ChipValence

    public init(id: UUID, domain: Domain, categoryID: UUID?, slug: String, label: String, valence: ChipValence) {
        self.id = id
        self.domain = domain
        self.categoryID = categoryID
        self.slug = slug
        self.label = label
        self.valence = valence
    }

    enum CodingKeys: String, CodingKey {
        case id, domain, slug, label, valence
        case categoryID = "category_id"
    }
}

/// A chip the user has actually applied to one of their items, with the
/// vocabulary row embedded so a sheet can render the label without a second
/// read. `week` is stamped at apply time and never recomputed — "broke me out
/// · week 1" and "· week 10" are opposite facts, and re-deriving the week on
/// read would quietly rewrite history every time the sheet opened.
public struct AppliedChip: Decodable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let chip: ExperienceChip
    public let week: Int?
    /// "Other" write-ins, which feed the weekly vocabulary review.
    public let freetext: String?

    public init(id: UUID, chip: ExperienceChip, week: Int?, freetext: String?) {
        self.id = id
        self.chip = chip
        self.week = week
        self.freetext = freetext
    }

    enum CodingKeys: String, CodingKey {
        case id, week, freetext
        /// The embedded resource arrives under the table's own name.
        case chip = "experience_chips"
    }
}

/// The pre-ranking signal on a shelf item (`user_items.like_state`, -1|0|1).
///
/// Deliberately named for what the column stores, not for anything a screen
/// might call it. GLO-87 is weighing whether "would repurchase" renders from
/// this, and that is a copy decision for Sean — the frozen core does not get
/// to prejudge it by naming a case `wouldRepurchase`.
public enum LikeState: Int, Codable, Sendable, CaseIterable {
    case disliked = -1
    case neutral = 0
    case liked = 1
}
