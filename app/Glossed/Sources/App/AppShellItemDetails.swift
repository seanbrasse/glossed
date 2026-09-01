import Collections
import DataKit
import DesignSystem
import Profile
import Routines
import SwiftUI

// The detail crossings (GLO-272): the profile's cards are `features/Profile`'s,
// the detail screens are `features/Collections`' and `features/Routines`', and
// features never import features — so the doors are wired here, exactly as
// `LookPostHost` is.

/// The collection or routine the profile opened. One identity for one cover:
/// two `@State`s could present two covers at once, and the shell has no
/// screen for that.
enum OpenOwnItem: Identifiable {
    case collection(UUID)
    case routine(UUID)
    /// The default want-to-try collection (batch 2) — virtual, so it has no
    /// row id; a fixed identity keeps the cover machinery uniform.
    case wantToTry

    var id: UUID {
        switch self {
        case let .collection(id), let .routine(id): id
        case .wantToTry: Self.wantToTryID
        }
    }

    /// Fixed and arbitrary — the case is a singleton screen, not a row.
    private static let wantToTryID = UUID(uuidString: "77A17771-0000-4000-8000-000000000001") ?? UUID()
}

extension AppShell {
    /// The cover the profile's collection/routine cards open.
    @ViewBuilder func ownItemDetail(_ item: OpenOwnItem) -> some View {
        if let client = session.client {
            switch item {
            case let .collection(id):
                CollectionDetailView(
                    collectionID: id,
                    store: .repository(
                        collections: CollectionsRepository(client: client),
                        shelf: ShelfRepository(client: client)
                    ),
                    onClose: { openOwnItem = nil },
                    onDeleted: { openOwnItem = nil }
                )
            case let .routine(id):
                RoutineDetailView(
                    load: { try await Self.loadRoutineDetail(id, client: client) },
                    editStore: Self.routineEditStore(id, client: client),
                    onClose: { openOwnItem = nil },
                    onDeleted: { openOwnItem = nil }
                )
            case .wantToTry:
                WantToTryDetailView(
                    store: Self.wantToTryStore(client: client, imageBase: session.imageBase),
                    onClose: { openOwnItem = nil }
                )
            }
        }
    }

    /// The default collection's read: shelf rows at `want_to_try`, catalog
    /// images composed from the app's own `imageBase` (GLO-74 — features
    /// never guess at it).
    static func wantToTryStore(client: GlossedClient, imageBase: URL?) -> WantToTryStore {
        let shelf = ShelfRepository(client: client)
        return WantToTryStore(entries: {
            try await shelf.shelf(status: .wantToTry).map { row in
                WantToTryEntry(
                    id: row.userItemID,
                    brand: row.brandName,
                    name: row.productName,
                    imageURL: row.catalogImageKey.flatMap { key in
                        imageBase?.appending(path: key)
                    }
                )
            }
        })
    }

    /// One routine, shaped for the detail screen: `mine()` (drafts and all —
    /// it is your own), steps as the composer's own type, links through the
    /// both-halves policy.
    static func loadRoutineDetail(
        _ routineID: UUID, client: GlossedClient
    ) async throws -> OwnRoutineDetail {
        let routines = RoutinesRepository(client: client)
        let links = LinksRepository(client: client)
        guard let mine = try await routines.mine().first(where: { $0.routineID == routineID }) else {
            throw GlossedError(.notFound, userMessage: "that routine didn't load — try again.")
        }
        let linked = await (try? links.linkedCollections(routineID: routineID)) ?? []
        return OwnRoutineDetail(
            title: mine.title,
            slotLabel: RoutineComposerModel.Slot(rawValue: mine.slot.rawValue)?.label
                ?? mine.slot.rawValue,
            visibility: mine.visibility,
            steps: mine.steps.map { step in
                RoutineComposerModel.Step(
                    id: step.userItemID,
                    name: step.productName,
                    brand: step.brandName,
                    note: step.note ?? ""
                )
            },
            collections: linked.map { LinkablePick(id: $0.id, title: $0.title) }
        )
    }

    /// The edit screen's writes, one closure per repository call — the
    /// `LookEditStore` wiring, for routines.
    static func routineEditStore(_ routineID: UUID, client: GlossedClient) -> RoutineEditStore {
        let routines = RoutinesRepository(client: client)
        let links = LinksRepository(client: client)
        let collections = CollectionsRepository(client: client)
        let shelf = ShelfRepository(client: client)
        return RoutineEditStore(
            rename: { try await routines.rename(routineID: routineID, to: $0) },
            setVisibility: { try await routines.setVisibility(routineID: routineID, to: $0) },
            replaceSteps: { drafts in
                try await routines.replaceSteps(
                    routineID: routineID,
                    with: drafts.map { RoutineDraft.Step(userItemID: $0.userItemID, note: $0.note) }
                )
            },
            linkCollections: { try await links.link(routineID: routineID, collectionIDs: $0) },
            unlinkCollection: { try await links.unlink(routineID: routineID, collectionID: $0) },
            remove: { try await routines.remove(routineID: routineID) },
            shelf: {
                try await shelf.shelf().map { row in
                    RoutineComposerModel.Step(
                        id: row.userItemID, name: row.productName, brand: row.brandName
                    )
                }
            },
            collections: {
                try await collections.mine().map {
                    LinkablePick(id: $0.collectionID, title: $0.title)
                }
            }
        )
    }
}
