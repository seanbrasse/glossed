import CoreGraphics
import DataKit
import Foundation
import Observation

/// One photo the composer holds, already past the on-device gates (SCA and
/// the EXIF strip live behind `PhotoPreparing` — GLO-198's seam; the
/// simulator has neither, and the composer must be drivable without them).
public struct ComposerPhoto: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let localData: Data
    public var position: Int

    public init(id: UUID = UUID(), localData: Data, position: Int) {
        self.id = id
        self.localData = localData
        self.position = position
    }
}

/// What the composer asks of the world, as closures (the TrendingStore
/// shape). `save` persists a draft and returns its id; `searchShelf` is the
/// pin-tag picker's source — you tag what you OWN (tech/03 §1), so this
/// searches the shelf, never the catalog.
/// Something a look can link (0050): one of YOUR routines or collections,
public struct LooksStore: Sendable {
    /// Takes the board's SPOTS since 0049 landed — the projection down to
    /// look-scoped single-product rows lived in `ComposerModelLegacyTags`
    /// and was deleted with it, exactly as its banner promised.
    public var save: @Sendable (_ caption: String, _ photos: [ComposerPhoto], _ spots: [LookTagSpot]) async throws
        -> UUID
    public var searchShelf: @Sendable (_ query: String) async throws -> [ShelfTagCandidate]
    /// The link section's offer (0050). Defaulted empty so a host that has
    /// not wired links renders no section — the no-dead-doors rule.
    public var linkables: @Sendable () async throws -> LookLinkables
    /// Writes the picked links after the draft lands. Defaulted to a no-op
    /// for the same reason.
    public var link: @Sendable (_ lookID: UUID, _ routineIDs: [UUID], _ collectionIDs: [UUID]) async throws -> Void

    public init(
        save: @escaping @Sendable (String, [ComposerPhoto], [LookTagSpot]) async throws -> UUID,
        searchShelf: @escaping @Sendable (String) async throws -> [ShelfTagCandidate],
        linkables: @escaping @Sendable () async throws -> LookLinkables = {
            LookLinkables(routines: [], collections: [])
        },
        link: @escaping @Sendable (UUID, [UUID], [UUID]) async throws -> Void = { _, _, _ in }
    ) {
        self.save = save
        self.searchShelf = searchShelf
        self.linkables = linkables
        self.link = link
    }
}

/// A shelf row as the tag picker sees it.
public struct ShelfTagCandidate: Identifiable, Sendable, Equatable {
    public let variantID: UUID
    public let label: String

    public var id: UUID {
        variantID
    }

    public init(variantID: UUID, label: String) {
        self.variantID = variantID
        self.label = label
    }
}

/// For the one call site that has no category to offer — the pre-board shelf
/// picker, which knows a variant and a label and nothing else. Internal
/// because it retires with that path; a tagged product in an honest bucket
/// beats one missing from the list.
extension TagCategory {
    static let unknown = TagCategory(slug: "", label: "uncategorized")
}

@MainActor
@Observable
public final class ComposerModel {
    public enum Phase: Equatable {
        case composing
        case saving
        /// The id, so the host can show the draft it just made.
        case saved(UUID)
    }

    public private(set) var phase: Phase = .composing
    public private(set) var photos: [ComposerPhoto] = []
    /// Every tag on this look — spots on photos, each holding an ordered set
    /// of products (GLO-266). **The single source of truth for tagging.**
    ///
    /// `internal(set)` rather than `private(set)`: the tagging canvas is a
    /// view in this package and drives the board through a `Binding`, so it
    /// needs write access. Outside the package it stays read-only, and the
    /// model keeps the invariants that matter (a removed photo takes its
    /// spots) in the methods that own them.
    public internal(set) var tagBoard = LookTagBoard()
    /// What the link section offers, loaded once. Empty renders no section.
    /// `internal(set)`: the links extension in this package mutates these —
    /// `tagBoard`'s reasoning, one file over.
    public internal(set) var linkables = LookLinkables(routines: [], collections: [])
    /// The picks, by id — sets because a link is on or off, and the write
    /// orders by the offer's own order at save time.
    public internal(set) var linkedRoutineIDs: Set<UUID> = []
    public internal(set) var linkedCollectionIDs: Set<UUID> = []
    /// The failed save's message, held until a retry answers (the sweep's
    /// triad: a failure names itself and keeps the way onward).
    public private(set) var saveFailure: String?
    public var caption = ""

    /// The cap is the composer's, not the database's — enforced here so the
    /// extreme state is designed rather than discovered (GLO-88's whole
    /// family).
    ///
    /// **Five, because Sean said five** (GLO-266: "adding multiple photos at
    /// once, with a limit of 5"). It was six, workshopped rather than
    /// specified; this is the specified number and it replaces the guess.
    /// Nothing downstream cares about the value — `look_photos.position` is
    /// dense from zero under `unique (look_id, position)` and `renumber()`
    /// keeps it so at any count — but the number itself is a product
    /// decision, so it changes deliberately and says why.
    public static let photoCap = 5
    public static let captionCap = 2200

    let store: LooksStore?
    public private(set) var saveTask: Task<Void, Never>?

    public init(store: LooksStore?) {
        self.store = store
    }

    /// How many more this look will take. The picker is bounded by THIS
    /// rather than by the cap, so a selection can never be larger than the
    /// room left — the overflow is prevented at the door instead of being
    /// silently trimmed after the fact.
    public var remainingPhotoSlots: Int {
        max(0, Self.photoCap - photos.count)
    }

    public var canAddPhoto: Bool {
        remainingPhotoSlots > 0
    }

    /// Post needs a photo — a look IS a photo post (tech/03 §1). The caption
    /// is optional; the photo is the point.
    public var canPost: Bool {
        !photos.isEmpty && phase == .composing && caption.count <= Self.captionCap
    }

    /// Several at once, in the order they were picked — GLO-266's first
    /// sentence ("adding multiple photos at once"). The picker hands back a
    /// SELECTION, so this is the primitive and the single-photo call is the
    /// convenience, not the other way round.
    ///
    /// A selection larger than the room left keeps its first photos and drops
    /// the rest rather than failing whole: the user picked in an order and the
    /// front of it is what they reached for first. The accepted count comes
    /// back so a caller can tell the difference between "all of them" and
    /// "as many as fit" — this model does not hold that as state, because a
    /// bounded picker (`remainingPhotoSlots`) means it should not arise.
    @discardableResult
    public func addPhotos(_ items: [Data]) -> Int {
        let room = remainingPhotoSlots
        guard room > 0 else { return 0 }
        let taken = items.prefix(room)
        // `position` is a placeholder here on purpose: `renumber()` is the one
        // path that assigns it, and a second piece of arithmetic in this
        // method is exactly what that comment forbids.
        photos.append(contentsOf: taken.map { ComposerPhoto(localData: $0, position: 0) })
        renumber()
        return taken.count
    }

    @discardableResult
    public func addPhoto(_ data: Data) -> Int {
        addPhotos([data])
    }

    /// **The behaviour GLO-266 changes.** A tag used to pin to the LOOK, so it
    /// survived its photo's removal — leaving coordinates into a photo that no
    /// longer existed. A tag pins to a PHOTO now, so it goes when the photo
    /// does.
    public func removePhoto(_ id: UUID) {
        photos.removeAll { $0.id == id }
        renumber()
        tagBoard.removeSpots(on: id)
    }

    /// Reorder. The dragged photo takes the destination's index and everything
    /// between shifts by one — the order the user sees is the order that
    /// saves, because `position` is rewritten from the array immediately
    /// after (GLO-232).
    ///
    /// Tags are untouched on purpose, and now for a better reason than before:
    /// a spot keys on its photo's IDENTITY, not on its position, so reordering
    /// cannot move a tag off the photo it was placed on.
    public func movePhoto(from source: Int, to destination: Int) {
        guard photos.indices.contains(source) else { return }
        let target = min(max(destination, 0), photos.count - 1)
        guard target != source else { return }
        photos.insert(photos.remove(at: source), at: target)
        renumber()
    }

    /// Convenience for the drop handler, which knows an identity rather than
    /// an index. Unknown ids are a no-op — a stale drag payload must not move
    /// somebody else's photo.
    public func movePhoto(_ id: UUID, to destination: Int) {
        guard let source = photos.firstIndex(where: { $0.id == id }) else { return }
        movePhoto(from: source, to: destination)
    }

    /// The ONE renumber path. `look_photos` is `unique (look_id, position)`
    /// and positions must stay dense from 0, so every mutation of the array
    /// ends here rather than growing its own arithmetic.
    ///
    /// Client-side only today: the composer holds photos in memory and writes
    /// once on save, so a reorder never issues the UPDATE that would collide
    /// against that unique index mid-statement. The day a saved look becomes
    /// editable, that write needs a deferred constraint or a two-phase
    /// renumber — noted here so it is not rediscovered.
    private func renumber() {
        for index in photos.indices {
            photos[index].position = index
        }
    }

    public func removeTag(_ variantID: UUID) {
        guard let placement = tagBoard.placement(of: variantID) else { return }
        tagBoard.remove(variantID, from: placement.spotID)
        tagBoard.discardEmptySpots()
    }

    /// The list under the photos, ordered by category, in the reader's own
    /// photo order (GLO-266: "a list of tagged products, ordered by category").
    public var tagListing: [LookTagListingGroup] {
        tagBoard.listing(photoOrder: photos.map(\.id))
    }

    /// Saves a DRAFT, and the copy around this must say so: until image
    /// moderation exists (GLO-26) nothing can honestly reach 'public', so
    /// the composer never promises a review that is not built (GLO-189).
    public func post() {
        guard canPost, let store else { return }
        phase = .saving
        saveFailure = nil
        saveTask = Task {
            do {
                let id = try await store.save(caption, photos, tagBoard.spots)
                // Links land after the draft, in the offer's own order. A
                // link that fails does NOT fail the post — the look is saved
                // and real; the miss is named so a retry exists.
                let routineIDs = linkables.routines.map(\.id).filter { linkedRoutineIDs.contains($0) }
                let collectionIDs = linkables.collections.map(\.id).filter { linkedCollectionIDs.contains($0) }
                if !routineIDs.isEmpty || !collectionIDs.isEmpty {
                    do {
                        try await store.link(id, routineIDs, collectionIDs)
                    } catch {
                        saveFailure = "your look saved, but linking didn't — you can link it again from the look."
                    }
                }
                phase = .saved(id)
            } catch {
                // Composing, not lost: everything typed and tagged is still
                // here, and the failure names itself beside a live retry.
                phase = .composing
                saveFailure = "that didn't save. your look is still here — try again."
            }
        }
    }
}
