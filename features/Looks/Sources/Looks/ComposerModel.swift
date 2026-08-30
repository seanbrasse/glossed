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

/// A pin on a photo: which variant, and where. Normalized coordinates so the
/// tag survives any render size — the DB checks the same 0...1 range (0043).
public struct ComposerTag: Identifiable, Sendable, Equatable {
    public let variantID: UUID
    public let label: String
    public var x: Double
    public var y: Double

    public var id: UUID {
        variantID
    }

    public init(variantID: UUID, label: String, x: Double, y: Double) {
        self.variantID = variantID
        self.label = label
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }
}

/// What the composer asks of the world, as closures (the TrendingStore
/// shape). `save` persists a draft and returns its id; `searchShelf` is the
/// pin-tag picker's source — you tag what you OWN (tech/03 §1), so this
/// searches the shelf, never the catalog.
public struct LooksStore: Sendable {
    public var save: @Sendable (_ caption: String, _ photos: [ComposerPhoto], _ tags: [ComposerTag]) async throws
        -> UUID
    public var searchShelf: @Sendable (_ query: String) async throws -> [ShelfTagCandidate]

    public init(
        save: @escaping @Sendable (String, [ComposerPhoto], [ComposerTag]) async throws -> UUID,
        searchShelf: @escaping @Sendable (String) async throws -> [ShelfTagCandidate]
    ) {
        self.save = save
        self.searchShelf = searchShelf
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
    public private(set) var tags: [ComposerTag] = []
    /// The failed save's message, held until a retry answers (the sweep's
    /// triad: a failure names itself and keeps the way onward).
    public private(set) var saveFailure: String?
    public var caption = ""

    /// The cap is the composer's, not the database's — a limit worth
    /// workshopping, enforced here so the extreme state is designed rather
    /// than discovered (GLO-88's whole family).
    public static let photoCap = 6
    public static let captionCap = 2200

    private let store: LooksStore?
    public private(set) var saveTask: Task<Void, Never>?

    public init(store: LooksStore?) {
        self.store = store
    }

    public var canAddPhoto: Bool {
        photos.count < Self.photoCap
    }

    /// Post needs a photo — a look IS a photo post (tech/03 §1). The caption
    /// is optional; the photo is the point.
    public var canPost: Bool {
        !photos.isEmpty && phase == .composing && caption.count <= Self.captionCap
    }

    public func addPhoto(_ data: Data) {
        guard canAddPhoto else { return }
        photos.append(ComposerPhoto(localData: data, position: photos.count))
    }

    public func removePhoto(_ id: UUID) {
        photos.removeAll { $0.id == id }
        for index in photos.indices {
            photos[index].position = index
        }
        // Tags pin to the look, not to a photo, so they survive a removal.
    }

    /// One tag per variant — re-tagging moves the pin rather than stacking a
    /// duplicate the DB would reject anyway (0043's primary key).
    public func tag(_ candidate: ShelfTagCandidate, x: Double, y: Double) {
        tags.removeAll { $0.variantID == candidate.variantID }
        tags.append(ComposerTag(variantID: candidate.variantID, label: candidate.label, x: x, y: y))
    }

    public func removeTag(_ variantID: UUID) {
        tags.removeAll { $0.variantID == variantID }
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
                let id = try await store.save(caption, photos, tags)
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
