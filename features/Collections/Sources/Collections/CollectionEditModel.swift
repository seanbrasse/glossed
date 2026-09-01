import DataKit
import Foundation

/// The collection edit screen's state (GLO-272) — the look edit pattern,
/// restated for this feature (features never import features, and the
/// pattern is smaller than a dependency): everything stages, `isDirty` arms
/// the save button on the first change, save writes only the diffs, and a
/// failure keeps every staged edit and names itself.
@Observable @MainActor
public final class CollectionEditModel {
    public struct Baseline: Equatable, Sendable {
        public var title: String
        public var description: String
        public var visibility: PrivacyScope
        public var items: [CollectionItem]

        public init(
            title: String, description: String?, visibility: PrivacyScope, items: [CollectionItem]
        ) {
            self.title = title
            self.description = description ?? ""
            self.visibility = visibility
            self.items = items
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
    public var description: String
    public var visibility: PrivacyScope
    public var items: [CollectionItem]
    public private(set) var phase = Phase.editing

    private let collectionID: UUID
    private let store: CollectionsStore

    public init(collectionID: UUID, baseline: Baseline, store: CollectionsStore) {
        self.collectionID = collectionID
        self.baseline = baseline
        title = baseline.title
        description = baseline.description
        visibility = baseline.visibility
        items = baseline.items
        self.store = store
    }

    /// Whitespace around the title is not a change; an EMPTY title is not a
    /// change either — it is invalid, and offering a save that will be
    /// refused is worse than staying disarmed.
    public var isDirty: Bool {
        (trimmedTitle != baseline.title && !trimmedTitle.isEmpty)
            || trimmedDescription != baseline.description
            || visibility != baseline.visibility
            || items.map(\.id) != baseline.items.map(\.id)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Diff-only, content before reach — the look model's order and its
    /// reason: if an item write dies, the collection has not widened first.
    /// The baseline moves up per landed write, so a failure keeps every
    /// staged edit and the retry writes only what still needs writing.
    public func save() async -> Bool {
        guard isDirty, phase != .saving else { return false }
        phase = .saving
        do {
            if trimmedTitle != baseline.title, !trimmedTitle.isEmpty {
                try await store.rename(collectionID, trimmedTitle)
                baseline.title = trimmedTitle
            }
            if trimmedDescription != baseline.description {
                // Emptied SENDS nil — clearing clears (the repository
                // encodes the null).
                try await store.setDescription(
                    collectionID, trimmedDescription.isEmpty ? nil : trimmedDescription
                )
                baseline.description = trimmedDescription
            }
            let baseIDs = Set(baseline.items.map(\.id))
            let nowIDs = Set(items.map(\.id))
            for removed in baseline.items where !nowIDs.contains(removed.id) {
                try await store.removeItem(collectionID, removed.id)
            }
            // Adds land after the surviving set, in staged order — `position`
            // is append-order here, the composer's own rule.
            for (offset, added) in items.filter({ !baseIDs.contains($0.id) }).enumerated() {
                try await store.addItem(collectionID, added.id, baseline.items.count + offset)
            }
            baseline.items = items
            if visibility != baseline.visibility {
                try await store.setVisibility(collectionID, visibility)
                baseline.visibility = visibility
            }
            phase = .editing
            return true
        } catch {
            phase = .failed(userMessage(for: error, fallback: "that didn't save — try again."))
            return false
        }
    }

    /// Soft delete — the grouping retracts, the shelf items stay. The VIEW
    /// owns the confirmation and the lost-progress warning.
    public func delete() async -> Bool {
        guard phase != .deleting else { return false }
        phase = .deleting
        do {
            try await store.remove(collectionID)
            return true
        } catch {
            phase = .failed(userMessage(for: error, fallback: "couldn't delete — try again."))
            return false
        }
    }

    /// What the shelf offers that this collection does not yet hold.
    public func addables() async -> [CollectionItem] {
        let held = Set(items.map(\.id))
        let shelf = await (try? store.shelf()) ?? []
        return shelf.filter { !held.contains($0.id) }
    }

    private func userMessage(for error: any Error, fallback: String) -> String {
        (error as? GlossedError)?.userMessage ?? fallback
    }
}
