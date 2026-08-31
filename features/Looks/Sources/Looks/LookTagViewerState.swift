import Foundation

/// What the tag viewer is showing, as a value (GLO-266).
///
/// Four of Sean's sentences are decisions rather than drawing, and all four
/// live here so they can be asserted without a view:
///
/// 1. *"Tags only show in the photo when the user clicks on the tag icon in
///    the bottom left"* — tags are **hidden by default**. The photo is the
///    content; the dots are an overlay you ask for.
/// 2. *"clicking a dot opens up the tag in the photo as a small overlay"* —
///    one spot open at a time.
/// 3. *"under each photo will be a list of tagged products, ordered by
///    category, and clicking them will also open the dot with product view on
///    the photo."*
/// 4. *"Tags could be across several photos, so clicking a product in the list
///    that is tagged in a different photo than the current will scroll to that
///    photo and then show the tag."* — that is `reveal(_:)`, one call.
///
/// **A look post is attributed content, never a claim** (GLO-196). Nothing
/// here counts anything but this look's own tags, and nothing it exposes is
/// shaped like evidence.
public struct LookTagViewerState: Sendable, Equatable {
    public let board: LookTagBoard
    /// The reader's order — the deck's own sorted `items`, by id.
    public let photoOrder: [UUID]

    /// Off until asked for. Reads as an assertion, per the naming rule.
    public private(set) var isRevealingTags = false
    public private(set) var showingIndex = 0
    /// Which dot is open as an overlay. Nil is "none".
    public private(set) var openSpotID: UUID?

    public init(board: LookTagBoard, photoOrder: [UUID]) {
        self.board = board
        self.photoOrder = photoOrder
    }

    // MARK: - reading

    public var showingPhotoID: UUID? {
        photoOrder.indices.contains(showingIndex) ? photoOrder[showingIndex] : nil
    }

    /// **Empty unless the toggle is on.** The one place rule 1 is enforced, so
    /// no view can accidentally draw a dot that was not asked for.
    public var visibleSpots: [LookTagSpot] {
        guard isRevealingTags, let photoID = showingPhotoID else { return [] }
        return board.spots(on: photoID)
    }

    /// The open overlay, and only if it belongs to the photo on screen — a
    /// spot on another photo has nothing to be an overlay ON.
    public var openSpot: LookTagSpot? {
        guard let openSpotID, let spot = board.spot(openSpotID) else { return nil }
        return spot.photoID == showingPhotoID ? spot : nil
    }

    public var listing: [LookTagListingGroup] {
        board.listing(photoOrder: photoOrder)
    }

    /// Whether the toggle has anything to reveal. A control with nothing
    /// behind it is not offered — the composer's rule, applied here.
    public var hasTags: Bool {
        !board.isEmpty
    }

    /// Whether the eye on a list row would take you somewhere else. Used to
    /// word the row, not to hide it: a product tagged on the photo you are
    /// already looking at still reveals its dot.
    public func isOnAnotherPhoto(_ placement: TagPlacement) -> Bool {
        placement.photoID != showingPhotoID
    }

    // MARK: - writing

    /// The bottom-left toggle. Turning tags off closes any open overlay too —
    /// an overlay is a dot opened, and there are no dots when tags are off.
    public mutating func toggleTags() {
        isRevealingTags.toggle()
        if !isRevealingTags {
            openSpotID = nil
        }
    }

    /// Paging. Closes the open overlay, because it belonged to the photo you
    /// just left.
    public mutating func show(index: Int) {
        guard photoOrder.indices.contains(index), index != showingIndex else { return }
        showingIndex = index
        openSpotID = nil
    }

    public mutating func show(photoID: UUID) {
        guard let index = photoOrder.firstIndex(of: photoID) else { return }
        show(index: index)
    }

    public mutating func open(spotID: UUID) {
        guard let spot = board.spot(spotID) else { return }
        // Opening a spot on another photo goes there first, rather than
        // showing an overlay floating over the wrong picture.
        show(photoID: spot.photoID)
        isRevealingTags = true
        openSpotID = spotID
    }

    public mutating func closeSpot() {
        openSpotID = nil
    }

    /// **Sean's cross-photo sentence, in one call.** Scroll to the photo the
    /// product is tagged on, turn the tags on, and open its dot — in that
    /// order, because the last two are meaningless before the first.
    ///
    /// An untagged variant is a no-op rather than a trap: a stale list row
    /// must not take the viewer down.
    @discardableResult
    public mutating func reveal(_ variantID: UUID) -> Bool {
        guard let placement = board.placement(of: variantID) else { return false }
        open(spotID: placement.spotID)
        return true
    }
}
