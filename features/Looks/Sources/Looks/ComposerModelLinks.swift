import Foundation

// The composer's link half (0050 — "link looks, collections, and routines
// together"). Its own file for the 300-line ceiling; the state it drives
// lives on the model, the way the tag board's canvas half does.

public extension ComposerModel {
    // MARK: - links (0050 — "link looks, collections, and routines together")

    func loadLinkables() async {
        guard let store else { return }
        linkables = await (try? store.linkables()) ?? LookLinkables(routines: [], collections: [])
    }

    func toggleRoutine(_ id: UUID) {
        if linkedRoutineIDs.contains(id) {
            linkedRoutineIDs.remove(id)
        } else {
            linkedRoutineIDs.insert(id)
        }
    }

    func toggleCollection(_ id: UUID) {
        if linkedCollectionIDs.contains(id) {
            linkedCollectionIDs.remove(id)
        } else {
            linkedCollectionIDs.insert(id)
        }
    }
}
