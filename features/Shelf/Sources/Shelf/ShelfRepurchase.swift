import DataKit
import Foundation

// GLO-87's "would you buy it again?", in its own file because `ShelfModel` is
// at SwiftLint's 300-line ceiling and stored properties cannot move to an
// extension — the house remedy is to extract the behaviour and leave the state
// behind (session 7's ShelfShownState scar, and AppShellProductPage after it).

@MainActor
public extension ShelfModel {
    /// Whether the question can be asked at all — a fixture state with no
    /// store must not offer a control that writes nowhere (GLO-72).
    var supportsRepurchase: Bool {
        likeStore != nil
    }

    /// Reads the saved answer when a sheet opens.
    ///
    /// Only a tried item is asked — the same predicate the fit gate and the
    /// chips already stand behind (GLO-87, GLO-145): you cannot say whether
    /// you would buy something again before you have used it.
    internal func loadRepurchase(for item: ShelfItem) {
        openRepurchase = nil
        persistedRepurchase = nil
        repurchaseEdited = false
        guard item.status.isTried, let likeStore else { return }
        likeLoadTask = Task { [id = item.id] in
            guard let saved = try? await likeStore.load(id) else { return }
            // Late answers do not overwrite: a different sheet, or an edit
            // made while the read was in flight, is newer than the read.
            guard !Task.isCancelled, openItem?.id == id, !repurchaseEdited else { return }
            openRepurchase = saved
            persistedRepurchase = saved
        }
    }

    /// The repurchase answer, written through with the same rules the fit
    /// answer uses: optimistic on screen, serialised so two saves cannot land
    /// out of order, and reverted to what is actually persisted if the write
    /// fails. Tapping the selected answer clears it — unanswered is a state
    /// you are allowed to return to.
    func repurchaseChanged(to answer: RepurchaseAnswer?) {
        guard let item = openItem, item.status.isTried else { return }
        openRepurchase = answer
        repurchaseEdited = true
        guard let likeStore else { return }
        likeSaveTask = Task { [previous = likeSaveTask, id = item.id] in
            await previous?.value
            do {
                try await likeStore.save(id, answer)
                guard openItem?.id == id else { return }
                persistedRepurchase = answer
            } catch {
                guard openItem?.id == id, openRepurchase == answer else { return }
                openRepurchase = persistedRepurchase
            }
        }
    }
}
