import Foundation

// Split from `LooksRepository.swift` for the 300-line file ceiling when the
// owner-side reads landed (GLO-230) — the same split `RoutinesModels.swift`
// and `ShelfRow.swift` are. Nothing was renamed on the way across.

/// `look_state` from 0043, mirrored exactly.
///
/// **Nothing screens a look.** A look goes from `draft` to `public` because its
/// owner said so, and no step runs in between — Sean's ruling, Aug 30, recorded
/// on GLO-238 and built by migration 0048. GLO-26 carries the moderation stack
/// and the launch gate; until it lands, this enum describes a two-state
/// transition wearing a four-label type.
///
/// `pendingReview` and `removed` are carried because the column can hold them,
/// **not because anything produces them**. 0048's with-check pins a client
/// write to `draft` or `public`, so neither is reachable from the app at all;
/// they decode rather than throw so that a row written by some future
/// service-role path cannot take a whole list down.
public enum LookState: String, Codable, Sendable, CaseIterable {
    case draft
    /// Unreachable from a client, and nothing on the server sets it today.
    case pendingReview = "pending_review"
    /// `public` is a Swift keyword, so the case is spelled differently from its
    /// wire value — the same trade `PrivacyScope.publicScope` makes, and this
    /// is the only place the difference should ever be visible.
    case publicState = "public"
    /// Unreachable from a client. `removed_at` is not in the `authenticated`
    /// update grant either.
    case removed
}

/// One photo on one of your looks.
///
/// `r2Key` is a storage-relative key, not a URL — the app composes the URL from
/// its own config, the way `ShelfRow.catalogImageKey` does. DataKit carries the
/// fact, not the bucket (GLO-74).
///
/// **A look photo is regulated data** (`docs/domain.md` §5: "swatch/look
/// photos"). The key identifies it; nothing here may reach a log, an analytics
/// prop or a breadcrumb.
public struct LookPhoto: Sendable, Equatable, Identifiable {
    public let photoID: UUID
    public let r2Key: String
    public let position: Int

    public var id: UUID {
        photoID
    }

    public init(photoID: UUID, r2Key: String, position: Int) {
        self.photoID = photoID
        self.r2Key = r2Key
        self.position = position
    }
}

/// One variant pinned to a look, at the point the user put it.
///
/// `x`/`y` are the pin's fractional position within the photo, as written by
/// the composer — `numeric` columns, so they cross as `Double`.
public struct LookTag: Sendable, Equatable {
    public let variantID: UUID
    public let x: Double
    public let y: Double

    public init(variantID: UUID, x: Double, y: Double) {
        self.variantID = variantID
        self.x = x
        self.y = y
    }
}

/// One of YOUR OWN looks, photos and tags included.
///
/// Distinct from anything the feed renders, and the difference is `state`: this
/// one carries your drafts, which no other reader may see. A type that could
/// stand in for both would put an unpublished photo one field-access away from
/// a public surface — the reason `MyRoutine` is not `BrowseRoutine`.
public struct MyLook: Sendable, Equatable, Identifiable {
    public let lookID: UUID
    public let caption: String?
    public let state: LookState
    /// Stamped by the `looks_stamp_posted_at` trigger when `state` becomes
    /// `public`, and set back to nil if it ever leaves. Never written by this
    /// client: `posted_at` is not in the `authenticated` update grant, and
    /// sending it raises `42501`.
    public let postedAt: Date?
    public let createdAt: Date
    /// In `position` order, always — see `assemble`.
    public let photos: [LookPhoto]
    public let tags: [LookTag]

    public var id: UUID {
        lookID
    }

    /// The n behind "N photos". Derived, never carried alongside the array, so
    /// a count cannot disagree with the thing counted.
    public var photoN: Int {
        photos.count
    }

    /// Whether strangers can already read this one. Reads as an assertion, per
    /// the naming rule.
    public var isPublished: Bool {
        state == .publicState
    }

    public init(
        lookID: UUID, caption: String?, state: LookState,
        postedAt: Date?, createdAt: Date, photos: [LookPhoto], tags: [LookTag]
    ) {
        self.lookID = lookID
        self.caption = caption
        self.state = state
        self.postedAt = postedAt
        self.createdAt = createdAt
        self.photos = photos
        self.tags = tags
    }
}
