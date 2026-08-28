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
/// **The live factory does not exist yet.** Of the five closures, the frozen
/// core supplies only `applyChip` today; `vocabulary` (experience_chips
/// read), `applied` (item_chips read), `remove`, and `saveNote` (user_items
/// note update) await a DataKit opening — asked on GLO-16. Wiring a factory
/// around one real call and four fakes would claim a write path that does
/// not exist; the seam ships first so the sheet is drivable and tested, and
/// `repository(_:)` lands with the opening.
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
}
