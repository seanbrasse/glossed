import CoreGraphics
import Foundation

/// Reading order: down the photos, then down the spots on each, then through
/// each spot's own products. A named type rather than a tuple so the three
/// numbers cannot be compared in the wrong order by accident.
private struct DocumentRank: Comparable {
    let photo: Int
    let spot: Int
    let product: Int

    static func < (lhs: DocumentRank, rhs: DocumentRank) -> Bool {
        (lhs.photo, lhs.spot, lhs.product) < (rhs.photo, rhs.spot, rhs.product)
    }
}

/// Where a product is tagged — which spot, on which photo. The answer to
/// Sean's cross-photo sentence: "clicking a product in the list that is
/// tagged in a different photo than the current will scroll to that photo and
/// then show the tag."
public struct TagPlacement: Sendable, Equatable {
    public let spotID: UUID
    public let photoID: UUID
}

/// One row of the list under the photos: the product, and where to go to see
/// it. It carries its own destination so the list never has to search the
/// board back for it at tap time.
public struct LookTagListingEntry: Identifiable, Sendable, Equatable {
    public let product: TaggedProduct
    public let placement: TagPlacement

    public var id: UUID {
        product.variantID
    }
}

/// The list, "ordered by category" (Sean's words).
public struct LookTagListingGroup: Identifiable, Sendable, Equatable {
    public let category: TagCategory
    public let entries: [LookTagListingEntry]

    public var id: String {
        category.slug
    }
}

/// Every tag on a look, across all of its photos.
///
/// Pure and `Equatable`. The four things the UI needs are all here and all
/// testable without a view or a database: **placement** (`place`),
/// **hit-testing** (`spot(at:)`), the **cross-photo lookup**
/// (`placement(of:)`), and the **category ordering** (`listing(photoOrder:)`).
///
/// **One rule holds the whole thing together: a variant is tagged at most
/// once on a look.** Tagging it somewhere else MOVES it. That is not a
/// convenience — it is what makes `placement(of:)` total and unambiguous, and
/// therefore what makes "clicking a product scrolls to its photo" a
/// well-defined instruction rather than a choice between two answers. It is
/// also what 0043's primary key already said, and what the composer's
/// `reTaggingAVariantMovesThePinRatherThanStacking` already asserts.
public struct LookTagBoard: Sendable, Equatable {
    public private(set) var spots: [LookTagSpot]

    /// Rebuilt through the same `add` every mutation uses, rather than taken
    /// on trust — a board loaded from rows that tagged one variant twice comes
    /// out obeying the one-place rule instead of quietly breaking
    /// `placement(of:)` for the rest of its life.
    public init(_ seed: [LookTagSpot] = []) {
        spots = []
        for spot in seed {
            spots.append(LookTagSpot(id: spot.id, photoID: spot.photoID, point: spot.point))
            for product in spot.products {
                add(product, to: spot.id)
            }
        }
        discardEmptySpots()
    }

    // MARK: - reading

    public var isEmpty: Bool {
        taggedProductCount == 0
    }

    /// This look's own tagged products. **A page indicator, not evidence**
    /// (GLO-196) — it counts what the author attributed and claims nothing.
    public var taggedProductCount: Int {
        spots.reduce(0) { $0 + $1.products.count }
    }

    /// The kit's own heading for the list, from `G.Feed`:
    /// `'products tagged in this look · ' + post.tagged.length`.
    public var listHeading: String {
        "products tagged in this look · \(taggedProductCount)"
    }

    public func spots(on photoID: UUID) -> [LookTagSpot] {
        spots.filter { $0.photoID == photoID }
    }

    public func spot(_ id: UUID) -> LookTagSpot? {
        spots.first { $0.id == id }
    }

    /// The cross-photo lookup. Total by construction: a variant lives in one
    /// spot or in none.
    public func placement(of variantID: UUID) -> TagPlacement? {
        spots.first { $0.holds(variantID) }
            .map { TagPlacement(spotID: $0.id, photoID: $0.photoID) }
    }

    /// Hit-testing, in the coordinate space the photo is actually drawn in.
    /// The NEAREST dot within `radius`, not the first one found — with
    /// overlapping touch targets, "first in the array" would make the answer
    /// depend on tagging order, which nobody can see.
    public func spot(
        at point: CGPoint,
        in size: CGSize,
        on photoID: UUID,
        radius: CGFloat = LookTagGeometry.dotHitRadius
    ) -> LookTagSpot? {
        let tap = TagPoint.of(point, in: size)
        return spots(on: photoID)
            .map { ($0, $0.point.distance(to: tap, in: size)) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?
            .0
    }

    // MARK: - the list, ordered by category

    /// Grouped by category, in **document order within each group** — down
    /// the photos in the order the reader sees them, then down the spots on
    /// each photo, then through each spot's own product order. So the list
    /// reads the same way the photos do.
    ///
    /// Groups themselves are ordered **alphabetically by category label**.
    /// That is a deliberate placeholder rather than a preference: the catalog
    /// exposes no canonical category rank (`Category` carries `slug`, `label`,
    /// `is_anchor`, `rank_unlock_min` and no order column), and an arbitrary
    /// hand-written order here would be a second source of truth. When a rank
    /// exists, it replaces exactly this one comparator.
    ///
    /// `photoOrder` is the reader's order — the composer's `position`, the
    /// deck's sorted `items`. Spots on a photo not in it sort last rather than
    /// vanishing: a tag must never be dropped from the list because a photo
    /// id went missing.
    public func listing(photoOrder: [UUID]) -> [LookTagListingGroup] {
        let photoRank = Dictionary(
            uniqueKeysWithValues: photoOrder.enumerated().map { ($0.element, $0.offset) }
        )
        var ranked: [(rank: DocumentRank, entry: LookTagListingEntry)] = []
        for (spotIndex, spot) in spots.enumerated() {
            for (productIndex, product) in spot.products.enumerated() {
                ranked.append((
                    DocumentRank(
                        photo: photoRank[spot.photoID] ?? photoOrder.count,
                        spot: spotIndex,
                        product: productIndex
                    ),
                    LookTagListingEntry(
                        product: product,
                        placement: TagPlacement(spotID: spot.id, photoID: spot.photoID)
                    )
                ))
            }
        }
        ranked.sort { $0.rank < $1.rank }

        var order: [TagCategory] = []
        var grouped: [String: [LookTagListingEntry]] = [:]
        for item in ranked {
            let category = item.entry.product.category
            if grouped[category.slug] == nil {
                order.append(category)
            }
            grouped[category.slug, default: []].append(item.entry)
        }
        return order
            .sorted { ($0.label, $0.slug) < ($1.label, $1.slug) }
            .map { LookTagListingGroup(category: $0, entries: grouped[$0.slug] ?? []) }
    }

    // MARK: - writing

    /// Puts a new, empty spot on a photo — the tap half of "you can tap on
    /// part of a photo and add a tag". It is empty because the search bar
    /// opens next; `discardEmptySpots()` cleans up a placement the user backed
    /// out of.
    ///
    /// Refuses inside `minimumSeparation` of an existing spot on the same
    /// photo and answers `nil`: two dots a thumb cannot separate are one dot
    /// with a bug. The existing spot is the one to add to, and a caller that
    /// wants that should hit-test first.
    public mutating func place(
        on photoID: UUID,
        at point: TagPoint,
        in size: CGSize,
        separation: CGFloat = LookTagGeometry.minimumSeparation
    ) -> UUID? {
        let crowded = spots(on: photoID).contains {
            $0.point.distance(to: point, in: size) < separation
        }
        guard !crowded else { return nil }
        let spot = LookTagSpot(photoID: photoID, point: point)
        spots.append(spot)
        return spot.id
    }

    public mutating func move(_ spotID: UUID, to point: TagPoint) {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return }
        spots[index].point = point
    }

    public mutating func removeSpot(_ spotID: UUID) {
        spots.removeAll { $0.id == spotID }
    }

    /// Every spot on a photo goes when the photo does. This is the half of
    /// photo-removal the old look-scoped tag could not do: a tag whose photo
    /// is gone has coordinates into nothing.
    public mutating func removeSpots(on photoID: UUID) {
        spots.removeAll { $0.photoID == photoID }
    }

    /// Adds a product to a spot, and enforces the one-place rule: if the
    /// variant is tagged anywhere else on this look, it MOVES here, and a spot
    /// left empty **by that move** is discarded — a dot with nothing behind it
    /// is not a tag.
    ///
    /// Only spots emptied by this move. An empty spot the user has just placed
    /// and not yet filled is mid-composition on some other photo, and tagging
    /// something over here must not delete the dot they are standing on.
    ///
    /// Returns false for an unknown spot rather than trapping: a stale spot id
    /// from a dismissed sheet must not take the composer down.
    @discardableResult
    public mutating func add(_ product: TaggedProduct, to spotID: UUID) -> Bool {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return false }
        var emptiedByTheMove: Set<UUID> = []
        let elsewhere = spots.indices.filter {
            spots[$0].id != spotID && spots[$0].holds(product.variantID)
        }
        for other in elsewhere {
            spots[other].remove(product.variantID)
            if spots[other].isEmpty {
                emptiedByTheMove.insert(spots[other].id)
            }
        }
        spots[index].add(product)
        spots.removeAll { emptiedByTheMove.contains($0.id) }
        return true
    }

    /// Untags one product. The spot stays, even emptied, because the user is
    /// usually about to put something else in it — `discardEmptySpots()` is
    /// the explicit way to sweep, and the composer calls it when a placement
    /// is abandoned rather than edited.
    public mutating func remove(_ variantID: UUID, from spotID: UUID) {
        guard let index = spots.firstIndex(where: { $0.id == spotID }) else { return }
        spots[index].remove(variantID)
    }

    public mutating func discardEmptySpots() {
        spots.removeAll(where: \.isEmpty)
    }
}
