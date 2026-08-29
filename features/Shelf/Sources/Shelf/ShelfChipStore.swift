import DataKit
import Foundation

/// One pickable experience chip, as the sheet needs it — feature-owned
/// because the frozen core has no `ExperienceChip` model yet (see the store
/// note below). Mirrors `experience_chips`: id, label, valence.
public struct ShelfChip: Identifiable, Equatable, Sendable {
    public enum Valence: String, Sendable {
        case like, dislike
    }

    public let id: UUID
    public let label: String
    public let valence: Valence

    public init(id: UUID, label: String, valence: Valence) {
        self.id = id
        self.label = label
        self.valence = valence
    }
}

/// How the sheet's chip section and note reach persistence (GLO-16). Same
/// shape as `ShelfFitStore`, for the same reasons: the model tests against a
/// recording stub, picker fixture states run with no store, and live wiring
/// is one line per side.
///
/// The live factory now exists. When this seam shipped, the frozen core
/// supplied only `applyChip` and wiring four fakes around it would have
/// claimed a write path that did not exist. #192's opening landed the other
/// four — `chipVocabulary`, `chips(itemID:)`, `removeChip`, `updateNote` —
/// so `repository(shelf:catalog:)` below is real on all five, and the sheet's
/// chip editor reaches the database instead of stopping at the seam.
public struct ShelfChipStore: Sendable {
    /// The pickable vocabulary for an item's category and domain — the fixed
    /// launch set (tech/01 §5), never free text (free text is the "other"
    /// write-in flow, not this).
    public var vocabulary: @Sendable (_ categorySlug: String, _ domain: Domain) async throws -> [ShelfChip]
    /// The chip ids already applied to this item.
    public var applied: @Sendable (_ itemID: UUID) async throws -> Set<UUID>
    /// Applies one chip. `startedOn` rides along so the server derives the
    /// week — "broke me out · week 1" and "· week 10" are opposite facts.
    public var apply: @Sendable (_ itemID: UUID, _ chipID: UUID, _ startedOn: Date?) async throws -> Void
    public var remove: @Sendable (_ itemID: UUID, _ chipID: UUID) async throws -> Void
    public var saveNote: @Sendable (_ itemID: UUID, _ note: String) async throws -> Void

    public init(
        vocabulary: @escaping @Sendable (String, Domain) async throws -> [ShelfChip],
        applied: @escaping @Sendable (UUID) async throws -> Set<UUID>,
        apply: @escaping @Sendable (UUID, UUID, Date?) async throws -> Void,
        remove: @escaping @Sendable (UUID, UUID) async throws -> Void,
        saveNote: @escaping @Sendable (UUID, String) async throws -> Void
    ) {
        self.vocabulary = vocabulary
        self.applied = applied
        self.apply = apply
        self.remove = remove
        self.saveNote = saveNote
    }

    /// The live path, across two repositories because the vocabulary is
    /// reference data and the applying is personal — `experience_chips` and
    /// `categories` are the same for everyone, `item_chips` and the note are
    /// not (GLO-16).
    ///
    /// The slug lookup is the one seam that is not a straight call. The core
    /// scopes chips by category *id* and the shelf only ever carries a slug,
    /// so the id is resolved from `categories(domain:)` first. A slug that
    /// resolves to nothing degrades to the domain-wide chips rather than
    /// throwing: an unknown category should cost you "oxidized", not the
    /// whole editor.
    public static func repository(
        shelf: ShelfRepository,
        catalog: CatalogRepository
    ) -> ShelfChipStore {
        ShelfChipStore(
            vocabulary: { slug, domain in
                let known = try await catalog.categories(domain: domain)
                    .map { (slug: $0.slug, id: $0.id) }
                let categoryID = ShelfChipStore.categoryID(forSlug: slug, in: known)
                return try await catalog
                    .chipVocabulary(domain: domain, categoryID: categoryID)
                    .map(ShelfChip.init)
            },
            applied: { itemID in
                try await Set(shelf.chips(itemID: itemID).map(\.chip.id))
            },
            apply: { itemID, chipID, startedOn in
                try await shelf.applyChip(itemID: itemID, chipID: chipID, startedOn: startedOn)
            },
            remove: { itemID, chipID in
                try await shelf.removeChip(itemID: itemID, chipID: chipID)
            },
            saveNote: { itemID, note in
                try await shelf.updateNote(itemID: itemID, to: ShelfChipStore.storedNote(from: note))
            }
        )
    }

    /// Slug to category id, the one seam in the live path that is not a
    /// straight call — the core scopes chips by id and the shelf only carries
    /// a slug.
    ///
    /// Pulled out as a function rather than left inline because the drive
    /// **cannot** prove it: the seed carries ten domain-wide chips and zero
    /// category-scoped ones, so narrowing and not narrowing return the same
    /// list and the screen looks identical either way. Untestable by driving
    /// and invisible when wrong is exactly the combination that earns a unit
    /// test.
    ///
    /// Takes slug/id pairs rather than `[Category]` for a dull reason worth
    /// recording: `Category` has no public memberwise init, so a test could
    /// not build one without decoding JSON, and DataKit is frozen. Pairs are
    /// what this function actually needs anyway.
    static func categoryID(forSlug slug: String, in categories: [(slug: String, id: UUID)]) -> UUID? {
        categories.first { $0.slug == slug }?.id
    }

    /// An emptied note clears the column rather than storing `""`. The two are
    /// the same to a reader and different to every query that asks whether a
    /// note exists, and "I deleted my note" should mean there is no note.
    /// Whitespace-only counts as emptied for the same reason.
    static func storedNote(from note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension ShelfChip {
    /// The core's vocabulary row as the sheet needs it. The valences are the
    /// same two words in both places and are mapped case by case anyway, so a
    /// new one added to `chip_valence` is a compile error here rather than a
    /// chip that silently renders as a like.
    init(_ chip: ExperienceChip) {
        let valence: Valence = switch chip.valence {
        case .like: .like
        case .dislike: .dislike
        }
        self.init(id: chip.id, label: chip.label, valence: valence)
    }
}
