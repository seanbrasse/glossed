import DataKit
import DesignSystem
import Foundation
import Observation

/// The sheet's chips-and-note state, one open item at a time (GLO-16).
///
/// Its own `@Observable` rather than more stored properties on `ShelfModel`:
/// the sheet's extras have their own lifecycle (reset per open, flushed on
/// close) and `ShelfModel` sits at the file-length ceiling. `ShelfModel`
/// owns one instance and forwards `open`/`close`.
///
/// Chips toggle optimistically and revert on failure, the fit section's
/// contract: the control never keeps showing an answer that did not persist.
/// The note saves once, on close — a keystroke-level save would turn one
/// thought into thirty writes.
@MainActor
@Observable
public final class ShelfChipsModel {
    public private(set) var vocabulary: [ShelfChip] = []
    public private(set) var appliedIDs: Set<UUID> = []
    public private(set) var isLoading = false
    /// The skincare week rule, surfaced (tech/01 §5): a reaction chip without
    /// a start date has no week, and "broke me out · week 1" vs "· week 10"
    /// are opposite facts. True after a toggle was refused for it.
    public private(set) var needsStartDate = false

    public var note: String = ""

    private var item: ShelfItem?
    private var persistedApplied: Set<UUID> = []
    private var persistedNote = ""
    private let store: ShelfChipStore?

    /// Internal, not private: tests await these to order the async work.
    var loadTask: Task<Void, Never>?
    var chipTask: Task<Void, Never>?
    var noteTask: Task<Void, Never>?

    public init(store: ShelfChipStore?) {
        self.store = store
    }

    public func open(_ item: ShelfItem) {
        self.item = item
        vocabulary = []
        appliedIDs = []
        persistedApplied = []
        needsStartDate = false
        note = item.note ?? ""
        persistedNote = note
        loadTask?.cancel()
        guard let store else { return }
        isLoading = true
        loadTask = Task { [id = item.id, slug = item.categorySlug, domain = item.domain] in
            defer { isLoading = false }
            async let vocab = store.vocabulary(slug, domain)
            async let current = store.applied(id)
            guard let loaded = try? await (vocab, current) else { return }
            guard !Task.isCancelled, self.item?.id == id else { return }
            vocabulary = loaded.0
            appliedIDs = loaded.1
            persistedApplied = loaded.1
        }
    }

    /// Close flushes the note — the one write that waits for the end of the
    /// thought. Chip writes have already happened by now.
    public func close() {
        flushNote()
        item = nil
        loadTask?.cancel()
        needsStartDate = false
    }

    public func toggle(_ chipID: UUID) {
        guard let item, let store, vocabulary.contains(where: { $0.id == chipID }) else { return }
        // The week rule: skincare reactions need a start date to have a week.
        // Refusing here beats writing a week-less reaction the aggregates
        // would count as timeless.
        if item.domain == .skincare, item.startedOn == nil, !appliedIDs.contains(chipID) {
            needsStartDate = true
            return
        }
        needsStartDate = false
        let applying = !appliedIDs.contains(chipID)
        if applying {
            appliedIDs.insert(chipID)
        } else {
            appliedIDs.remove(chipID)
        }
        chipTask = Task { [previous = chipTask, id = item.id, startedOn = item.startedOn] in
            await previous?.value
            do {
                if applying {
                    try await store.apply(id, chipID, startedOn)
                } else {
                    try await store.remove(id, chipID)
                }
                guard self.item?.id == id else { return }
                persistedApplied = appliedIDs
            } catch {
                // Only the current sheet reverts, and only to what the store
                // last confirmed — a stale failure says nothing about newer
                // toggles already in flight behind it.
                guard self.item?.id == id else { return }
                appliedIDs = persistedApplied
            }
        }
    }

    /// The item's week today, for the chip section's caption ("week 3").
    public var currentWeek: Int? {
        guard let item else { return nil }
        return ShelfRepository.week(startedOn: item.startedOn, loggedOn: Date())
    }

    private func flushNote() {
        guard let item, let store, note != persistedNote else { return }
        noteTask = Task { [id = item.id, text = note] in
            try? await store.saveNote(id, text)
        }
    }
}
