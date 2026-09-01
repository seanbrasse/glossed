import DataKit
import Foundation

// The rename machinery, split from `ProfileTabsModel.swift` for the 300-line
// ceiling when the want-to-try store landed. NOTE: this whole family is
// GLO-279's deletion target — the edit-profile button that armed it is gone,
// and the edit screens own renames now.

extension ProfileTabsModel {
    /// Guarded on the TARGET's writer, not on the tab now showing — the same
    /// rule `saveRename` follows, and for the same reason: a tab switched
    /// under an open sheet must not decide what a rename means. `canRename`
    /// is the *button's* gate, and emptiness is not a reason to refuse a
    /// target that was handed over.
    public func beginRename(_ target: RenameTarget) {
        guard isEditing, renameWrite(for: target.tabForKind) != nil else { return }
        errorMessage = nil
        renaming = target
    }

    func renameWrite(for tab: ProfileTab) -> (@Sendable (UUID, String) async throws -> Void)? {
        switch tab {
        case .routines: routinesStore?.rename
        case .collections: collectionsStore?.rename
        case .looks, .shelf: nil
        }
    }

    /// Writes the new title, then updates the row in place.
    ///
    /// In place rather than by reloading: the write returned, so the stored
    /// title is the trimmed string that was sent, and a reload would flash a
    /// spinner over a list that is already correct. The trim is done here as
    /// well as in the repository so the two cannot disagree about what landed.
    ///
    /// A blank title is refused before the round trip, in the repository's own
    /// words — `routines.title` is `not null` but has no length check, and a
    /// routine with a blank name is unaddressable in a list.
    public func saveRename() async {
        guard let target = renaming, let write = renameWrite(for: target.tabForKind) else { return }
        let trimmed = target.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "give it a name."
            return
        }
        isSavingRename = true
        defer { isSavingRename = false }
        errorMessage = nil
        do {
            try await write(target.id, trimmed)
            apply(trimmed, to: target)
            renaming = nil
        } catch {
            // The sheet stays open with what was typed. A rename that closes
            // on failure loses the words and tells you it worked.
            errorMessage = (error as? GlossedError)?.userMessage ?? "that didn't save. try again."
        }
    }

    func apply(_ title: String, to target: RenameTarget) {
        switch target.kind {
        case .routine:
            routines = routines.map {
                guard $0.routineID == target.id else { return $0 }
                return MyRoutine(
                    routineID: $0.routineID, title: title, slot: $0.slot,
                    visibility: $0.visibility,
                    startedOn: $0.startedOn, createdAt: $0.createdAt, steps: $0.steps
                )
            }
        case .collection:
            collections = collections.map {
                guard $0.id == target.id else { return $0 }
                return ProfileCollection(
                    id: $0.id, title: title, tint: $0.tint,
                    itemN: $0.itemN, visibility: $0.visibility
                )
            }
        }
    }
}
