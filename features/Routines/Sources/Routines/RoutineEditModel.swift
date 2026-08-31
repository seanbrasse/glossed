import DataKit
import Foundation
import Observation

/// What the edit screen can do to a routine, as closures the app fills —
/// `RoutineStore`'s sibling, scoped to ONE routine so every closure already
/// knows which row it writes.
public struct RoutineEditStore: Sendable {
    public var rename: @Sendable (String) async throws -> Void
    public var setVisibility: @Sendable (PrivacyScope) async throws -> Void
    /// SET semantics — the whole step list, positions from array order
    /// (`RoutinesRepository.replaceSteps`).
    public var replaceSteps: @Sendable ([StepDraft]) async throws -> Void
    public var linkCollections: @Sendable ([UUID]) async throws -> Void
    public var unlinkCollection: @Sendable (UUID) async throws -> Void
    /// Soft delete — the routine retracts, its history stays.
    public var remove: @Sendable () async throws -> Void
    public var shelf: @Sendable () async throws -> [RoutineComposerModel.Step]
    public var collections: @Sendable () async throws -> [LinkablePick]

    public init(
        rename: @escaping @Sendable (String) async throws -> Void,
        setVisibility: @escaping @Sendable (PrivacyScope) async throws -> Void,
        replaceSteps: @escaping @Sendable ([StepDraft]) async throws -> Void,
        linkCollections: @escaping @Sendable ([UUID]) async throws -> Void,
        unlinkCollection: @escaping @Sendable (UUID) async throws -> Void,
        remove: @escaping @Sendable () async throws -> Void,
        shelf: @escaping @Sendable () async throws -> [RoutineComposerModel.Step],
        collections: @escaping @Sendable () async throws -> [LinkablePick] = { [] }
    ) {
        self.rename = rename
        self.setVisibility = setVisibility
        self.replaceSteps = replaceSteps
        self.linkCollections = linkCollections
        self.unlinkCollection = unlinkCollection
        self.remove = remove
        self.shelf = shelf
        self.collections = collections
    }
}

/// The routine edit screen's state (GLO-272) — the look/collection pattern,
/// restated here because features never import features: everything stages,
/// `isDirty` arms the save on the first change, save writes only the diffs
/// (content before reach), and a failure keeps every staged edit.
///
/// The SLOT is displayed, never edited: an am routine that becomes a pm
/// routine is a different routine — the composer's cadence identity rule.
@Observable @MainActor
public final class RoutineEditModel {
    public struct Baseline: Equatable, Sendable {
        public var title: String
        public var visibility: PrivacyScope
        public var steps: [RoutineComposerModel.Step]
        public var collections: [LinkablePick]

        public init(
            title: String, visibility: PrivacyScope,
            steps: [RoutineComposerModel.Step], collections: [LinkablePick]
        ) {
            self.title = title
            self.visibility = visibility
            self.steps = steps
            self.collections = collections
        }
    }

    public enum Phase: Equatable {
        case editing
        case saving
        case deleting
        case failed(String)
    }

    public private(set) var baseline: Baseline
    public var title: String
    public var visibility: PrivacyScope
    /// Steps stage whole — order, membership, and each step's NOTE ("three
    /// drops, pressed in"), which was Sean's per-step ask and is why a note
    /// edit alone must arm the save.
    public var steps: [RoutineComposerModel.Step]
    public var collections: [LinkablePick]
    public private(set) var phase = Phase.editing

    private let store: RoutineEditStore

    public init(baseline: Baseline, store: RoutineEditStore) {
        self.baseline = baseline
        title = baseline.title
        visibility = baseline.visibility
        steps = baseline.steps
        collections = baseline.collections
        self.store = store
    }

    public var isDirty: Bool {
        (trimmedTitle != baseline.title && !trimmedTitle.isEmpty)
            || visibility != baseline.visibility
            || stepsChanged
            || collections.map(\.id) != baseline.collections.map(\.id)
    }

    /// Membership, order, OR a note — all three are the step set.
    /// Whitespace-only note churn is not a change: the write path trims, so
    /// offering a save for it would save nothing.
    private var stepsChanged: Bool {
        normalized(steps) != normalized(baseline.steps)
    }

    private func normalized(_ steps: [RoutineComposerModel.Step]) -> [StepDraft] {
        steps.map {
            StepDraft(
                userItemID: $0.id,
                note: $0.note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Diff-only, content before reach; the baseline advances per landed
    /// write, so a failure keeps every staged edit and the retry writes only
    /// what is still owed.
    public func save() async -> Bool {
        guard isDirty, phase != .saving else { return false }
        phase = .saving
        do {
            if trimmedTitle != baseline.title, !trimmedTitle.isEmpty {
                try await store.rename(trimmedTitle)
                baseline.title = trimmedTitle
            }
            if stepsChanged {
                try await store.replaceSteps(normalized(steps))
                baseline.steps = steps
            }
            let baseIDs = Set(baseline.collections.map(\.id))
            let nowIDs = Set(collections.map(\.id))
            let adds = collections.map(\.id).filter { !baseIDs.contains($0) }
            if !adds.isEmpty {
                try await store.linkCollections(adds)
            }
            for removed in baseline.collections.map(\.id) where !nowIDs.contains(removed) {
                try await store.unlinkCollection(removed)
            }
            baseline.collections = collections
            if visibility != baseline.visibility {
                try await store.setVisibility(visibility)
                baseline.visibility = visibility
            }
            phase = .editing
            return true
        } catch {
            phase = .failed(userMessage(for: error, fallback: "that didn't save — try again."))
            return false
        }
    }

    public func delete() async -> Bool {
        guard phase != .deleting else { return false }
        phase = .deleting
        do {
            try await store.remove()
            return true
        } catch {
            phase = .failed(userMessage(for: error, fallback: "couldn't delete — try again."))
            return false
        }
    }

    /// What the shelf offers that this routine does not yet sequence.
    public func addableSteps() async -> [RoutineComposerModel.Step] {
        let held = Set(steps.map(\.id))
        let shelf = await (try? store.shelf()) ?? []
        return shelf.filter { !held.contains($0.id) }
    }

    /// Collections the routine could link and has not.
    public func addableCollections() async -> [LinkablePick] {
        let held = Set(collections.map(\.id))
        let offer = await (try? store.collections()) ?? []
        return offer.filter { !held.contains($0.id) }
    }

    private func userMessage(for error: any Error, fallback: String) -> String {
        (error as? GlossedError)?.userMessage ?? fallback
    }
}
