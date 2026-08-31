import DataKit
import Foundation

/// What the edit screen can do to a look, as closures the app fills — the
/// `LooksStore` pattern. Each closure is one repository write; the MODEL
/// decides which of them a save actually needs, so an edit that only moved
/// a tag never touches the caption row.
public struct LookEditStore: Sendable {
    public var updateCaption: @Sendable (String?) async throws -> Void
    public var setVisibility: @Sendable (PrivacyScope) async throws -> Void
    /// true → publish, false → unpost (back to draft).
    public var setPosted: @Sendable (Bool) async throws -> Void
    public var replaceSpots: @Sendable (LookTagBoard) async throws -> Void
    public var setLinks: @Sendable (LookLinkChanges) async throws -> Void
    public var linkables: @Sendable () async throws -> LookLinkables
    public var delete: @Sendable () async throws -> Void

    public init(
        updateCaption: @escaping @Sendable (String?) async throws -> Void,
        setVisibility: @escaping @Sendable (PrivacyScope) async throws -> Void,
        setPosted: @escaping @Sendable (Bool) async throws -> Void,
        replaceSpots: @escaping @Sendable (LookTagBoard) async throws -> Void,
        setLinks: @escaping @Sendable (LookLinkChanges) async throws -> Void,
        linkables: @escaping @Sendable () async throws -> LookLinkables,
        delete: @escaping @Sendable () async throws -> Void
    ) {
        self.updateCaption = updateCaption
        self.setVisibility = setVisibility
        self.setPosted = setPosted
        self.replaceSpots = replaceSpots
        self.setLinks = setLinks
        self.linkables = linkables
        self.delete = delete
    }
}

/// A staged link edit, as diffs — adds and removes computed by the model, so
/// the store writes exactly what changed and an untouched link is never
/// re-written.
public struct LookLinkChanges: Sendable, Equatable {
    public let addRoutineIDs: [UUID]
    public let removeRoutineIDs: [UUID]
    public let addCollectionIDs: [UUID]
    public let removeCollectionIDs: [UUID]

    public var isEmpty: Bool {
        addRoutineIDs.isEmpty && removeRoutineIDs.isEmpty
            && addCollectionIDs.isEmpty && removeCollectionIDs.isEmpty
    }
}

/// The edit screen's state (GLO-272, Sean's uniform pattern): everything
/// stages locally, `isDirty` arms the save button on the first change, and
/// `save` writes only the diffs. Images are deliberately not here — the
/// ruling makes them immutable after the composer.
@Observable @MainActor
public final class LookEditModel {
    /// What the look looked like when editing began — the baseline every
    /// dirtiness question compares against, and what a failed save leaves
    /// UNTOUCHED so retrying re-diffs correctly.
    public struct Baseline: Equatable, Sendable {
        public var caption: String
        public var visibility: PrivacyScope
        public var isPosted: Bool
        public var board: LookTagBoard
        public var routines: [LinkablePick]
        public var collections: [LinkablePick]

        public init(
            caption: String?, visibility: PrivacyScope, isPosted: Bool,
            board: LookTagBoard, routines: [LinkablePick], collections: [LinkablePick]
        ) {
            self.caption = caption ?? ""
            self.visibility = visibility
            self.isPosted = isPosted
            self.board = board
            self.routines = routines
            self.collections = collections
        }
    }

    public enum Phase: Equatable {
        case editing
        case saving
        case deleting
        /// A write refused or died. The staged edits are all still here —
        /// failure names itself and loses nothing (the house rule).
        case failed(String)
    }

    public private(set) var baseline: Baseline
    public var caption: String
    public var visibility: PrivacyScope
    public var isPosted: Bool
    public var board: LookTagBoard
    public var routines: [LinkablePick]
    public var collections: [LinkablePick]
    public private(set) var phase = Phase.editing

    private let store: LookEditStore

    public init(baseline: Baseline, store: LookEditStore) {
        self.baseline = baseline
        caption = baseline.caption
        visibility = baseline.visibility
        isPosted = baseline.isPosted
        board = baseline.board
        routines = baseline.routines
        collections = baseline.collections
        self.store = store
    }

    /// Arms the save button. A caption trimmed to its baseline is NOT a
    /// change — "typed a space and deleted it" must not offer a save.
    public var isDirty: Bool {
        trimmedCaption != baseline.caption
            || visibility != baseline.visibility
            || isPosted != baseline.isPosted
            || board != baseline.board
            || routines.map(\.id) != baseline.routines.map(\.id)
            || collections.map(\.id) != baseline.collections.map(\.id)
    }

    public var linkChanges: LookLinkChanges {
        let baseRoutines = Set(baseline.routines.map(\.id))
        let nowRoutines = Set(routines.map(\.id))
        let baseCollections = Set(baseline.collections.map(\.id))
        let nowCollections = Set(collections.map(\.id))
        return LookLinkChanges(
            addRoutineIDs: routines.map(\.id).filter { !baseRoutines.contains($0) },
            removeRoutineIDs: baseline.routines.map(\.id).filter { !nowRoutines.contains($0) },
            addCollectionIDs: collections.map(\.id).filter { !baseCollections.contains($0) },
            removeCollectionIDs: baseline.collections.map(\.id).filter { !nowCollections.contains($0) }
        )
    }

    private var trimmedCaption: String {
        caption.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Writes ONLY what changed, then moves the baseline up to match — so a
    /// second save with no further edits is a no-op, not a re-write.
    ///
    /// Not atomic across writes (they are separate PostgREST calls), and the
    /// order is deliberate: content first (spots, caption, links), REACH last
    /// (visibility, then state). If a content write fails, the look has not
    /// widened; nobody is shown half an edit at a scope it did not have when
    /// the edit began.
    ///
    /// Returns true when everything landed. On failure the phase names the
    /// half that failed and every staged edit survives for the retry.
    public func save() async -> Bool {
        guard isDirty, phase != .saving else { return false }
        phase = .saving
        do {
            if board != baseline.board {
                try await store.replaceSpots(board)
                baseline.board = board
            }
            if trimmedCaption != baseline.caption {
                try await store.updateCaption(trimmedCaption.isEmpty ? nil : trimmedCaption)
                baseline.caption = trimmedCaption
            }
            let links = linkChanges
            if !links.isEmpty {
                try await store.setLinks(links)
                baseline.routines = routines
                baseline.collections = collections
            }
            if visibility != baseline.visibility {
                try await store.setVisibility(visibility)
                baseline.visibility = visibility
            }
            if isPosted != baseline.isPosted {
                try await store.setPosted(isPosted)
                baseline.isPosted = isPosted
            }
            phase = .editing
            return true
        } catch {
            phase = .failed(userMessage(for: error, fallback: "that didn't save — try again."))
            return false
        }
    }

    /// The one irreversible write. The VIEW owns the confirmation ("warns of
    /// lost progress" — Sean's spec); by the time this runs, the user has
    /// already said yes.
    public func delete() async -> Bool {
        guard phase != .deleting else { return false }
        phase = .deleting
        do {
            try await store.delete()
            return true
        } catch {
            phase = .failed(userMessage(for: error, fallback: "couldn't delete — try again."))
            return false
        }
    }

    public func loadLinkables() async -> LookLinkables? {
        try? await store.linkables()
    }

    private func userMessage(for error: any Error, fallback: String) -> String {
        (error as? GlossedError)?.userMessage ?? fallback
    }
}
