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

        public init(id: UUID, name: String, brand: String) {
            self.id = id
            self.name = name
            self.brand = brand
        }
    }

    public var title = ""
    public var slot = Slot.am
    public private(set) var steps: [Step] = []
    /// The shelf to pick from, loaded once — empty is a state the screen
    /// explains (a routine needs things to sequence).
    public private(set) var shelf: [Step] = []
    public private(set) var isLoadingShelf = true
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
                    steps.map(\.id)
                )
                onSaved()
            } catch {
                guard !Task.isCancelled else { return }
                saveError = GlossedError.from(error)
            }
        }
    }
}

/// The seams the app fills — the shelf read exists today
/// (`ShelfRepository.shelf()`); the create is the third DataKit opening's
/// write and stays a closure until it is granted and landed.
public struct RoutineStore: Sendable {
    public var shelf: @Sendable () async throws -> [RoutineComposerModel.Step]
    public var create: @Sendable (_ title: String, _ slot: String, _ stepItemIDs: [UUID]) async throws -> Void

    public init(
        shelf: @escaping @Sendable () async throws -> [RoutineComposerModel.Step],
        create: @escaping @Sendable (String, String, [UUID]) async throws -> Void
    ) {
        self.shelf = shelf
        self.create = create
    }
}
