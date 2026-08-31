import DataKit
import Foundation
import Observation

/// The routine composer's state (GLO-21's CRUD half): a title, one slot,
/// and ordered steps picked FROM THE SHELF — a routine is a sequence of
/// things you own, never of catalog abstractions, which is why steps are
/// `user_item_id`s in the schema and shelf rows here.
///
/// **This screen says nothing about who can see a routine** (GLO-208). It
/// cannot: `routines` has no visibility column, and read access is decided at
/// SELECT time by `can_view(user_id, 'routines')` against the owner's
/// `privacy_scopes` row — which the privacy screen's `everything` control can
/// flip in one tap, from somewhere else, at any time. A claim here would be
/// true only until that tap, and a live read would go stale the same way while
/// looking verified. The privacy screen owns that question and answers it with
/// a live control; this one composes.
@MainActor
@Observable
public final class RoutineComposerModel {
    /// The schema's own vocabulary (`routine_slot`), worn with spaces.
    public enum Slot: String, CaseIterable, Sendable {
        case am, pm, weekly
        case washDay = "wash_day"

        public var label: String {
            self == .washDay ? "wash day" : rawValue
        }
    }

    /// One pickable/picked shelf row — the composer needs no more of the
    /// shelf than this.
    public struct Step: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let brand: String
        /// The owner's words on what they do in this step (0052) — "three
        /// drops, pressed in", not a second product name. Editable in place;
        /// the schema bounds it at 500 and `noteCap` matches, the
        /// captionCap pattern.
        public var note: String = ""

        public init(id: UUID, name: String, brand: String, note: String = "") {
            self.id = id
            self.name = name
            self.brand = brand
            self.note = note
        }
    }

    /// The schema's own bound (`routine_steps_note_length`), worn client-side
    /// so the refusal happens at the keyboard rather than as a 23514.
    public static let noteCap = 500

    public var title = ""
    public var slot = Slot.am
    public var steps: [Step] = []
    /// The shelf to pick from, loaded once — empty is a state the screen
    /// explains (a routine needs things to sequence).
    public private(set) var shelf: [Step] = []
    public private(set) var isLoadingShelf = true
    /// Collections this routine will link (0052) — offered from your own,
    /// because the write policy refuses anyone else's.
    public private(set) var linkableCollections: [LinkablePick] = []
    public private(set) var linkedCollectionIDs: Set<UUID> = []
    public private(set) var isSaving = false
    public private(set) var saveError: GlossedError?

    private let store: RoutineStore?
    var task: Task<Void, Never>?

    public init(store: RoutineStore? = nil) {
        self.store = store
    }

    public func loadShelf() {
        task?.cancel()
        guard let store else {
            isLoadingShelf = false
            return
        }
        task = Task {
            let rows = await (try? store.shelf()) ?? []
            guard !Task.isCancelled else { return }
            shelf = rows
            isLoadingShelf = false
            linkableCollections = await (try? store.collections()) ?? []
        }
    }

    public func toggleCollection(_ id: UUID) {
        if linkedCollectionIDs.contains(id) {
            linkedCollectionIDs.remove(id)
        } else {
            linkedCollectionIDs.insert(id)
        }
    }

    // MARK: - steps

    /// Tapping a shelf row toggles it: in appends to the END (order is the
    /// routine's meaning — appending respects the order you tapped in),
    /// out removes it wherever it sits.
    public func toggle(_ step: Step) {
        if let index = steps.firstIndex(where: { $0.id == step.id }) {
            steps.remove(at: index)
        } else {
            steps.append(step)
        }
    }

    public func isPicked(_ step: Step) -> Bool {
        steps.contains { $0.id == step.id }
    }

    /// Reorder by neighbor swap — the two arrows every row wears. Clamped:
    /// moving the first up or the last down is a no-op, not a crash.
    public func move(_ step: Step, up: Bool) {
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { return }
        let target = up ? index - 1 : index + 1
        guard steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
    }

    // MARK: - save

    /// A routine needs a name and at least one step — a titled empty
    /// sequence is a note, not a routine.
    public var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !steps.isEmpty
    }

    public func save(onSaved: @escaping () -> Void) {
        guard canSave else { return }
        guard let store else {
            onSaved()
            return
        }
        isSaving = true
        saveError = nil
        task = Task {
            defer { isSaving = false }
            do {
                try await store.create(
                    title.trimmingCharacters(in: .whitespacesAndNewlines),
                    slot.rawValue,
                    steps.map { StepDraft(userItemID: $0.id, note: $0.note) },
                    linkableCollections.map(\.id).filter { linkedCollectionIDs.contains($0) }
                )
                onSaved()
            } catch {
                guard !Task.isCancelled else { return }
                saveError = GlossedError.from(error)
            }
        }
    }
}

/// One step as the save hands it over: the shelf row, and the note the owner
/// typed for it. A pair rather than parallel arrays, so a reorder can never
/// hand step three its neighbor''s words.
public struct StepDraft: Sendable, Equatable {
    public let userItemID: UUID
    public let note: String

    public init(userItemID: UUID, note: String) {
        self.userItemID = userItemID
        self.note = note
    }
}

/// The seams the app fills — the shelf read exists today
/// (`ShelfRepository.shelf()`); the create maps to `RoutineDraft` at the app
/// layer.
/// A collection the routine could link, as a pickable chip (0052).
public struct LinkablePick: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

public struct RoutineStore: Sendable {
    public var shelf: @Sendable () async throws -> [RoutineComposerModel.Step]
    public var create: @Sendable (
        _ title: String, _ slot: String, _ steps: [StepDraft], _ linkedCollectionIDs: [UUID]
    ) async throws -> Void
    /// The link section's offer — your own collections. Defaulted empty so a
    /// host that has not wired links renders no section.
    public var collections: @Sendable () async throws -> [LinkablePick]

    public init(
        shelf: @escaping @Sendable () async throws -> [RoutineComposerModel.Step],
        create: @escaping @Sendable (String, String, [StepDraft], [UUID]) async throws -> Void,
        collections: @escaping @Sendable () async throws -> [LinkablePick] = { [] }
    ) {
        self.shelf = shelf
        self.create = create
        self.collections = collections
    }
}
