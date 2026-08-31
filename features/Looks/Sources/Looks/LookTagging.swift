import CoreGraphics
import DesignSystem
import Foundation

// The tag, as a value (GLO-266). Sean's model, in his words: "a user can add
// multiple tags to a photo, and each tag being in a spot, tags can hold
// several products each."
//
// So a tag is TWO things the current schema is one of: a **spot on a photo**,
// and an **ordered set of products** in that spot. Both are modelled here,
// pure and `Equatable`, the way `LookMediaDeck` was (GLO-235) — placement,
// hit-testing, the cross-photo lookup and the category ordering are all
// decisions worth assertions rather than gesture closures nobody can run.
//
// **No migration is needed for any of this.** The board is keyed by a photo's
// UUID, which the composer already has (`ComposerPhoto.id`) and the viewer
// already has (`LookMedia.id`); the peer lane's `look_tags(id, look_photo_id,
// x, y)` + `look_tag_variants(look_tag_id, variant_id, position)` maps onto it
// one-for-one when it lands.
//
// **A look post is attributed content, never a claim** (GLO-196). Nothing in
// this file counts anything but this look's own tags, and `countLine` is a
// page indicator — there is no n here, no cohort and no sample size.

/// A point on a photo, normalized to 0...1 in both axes, clamped on the way
/// in. Normalized rather than in points because a tag has to survive the
/// composer's 104pt tile, the deck's 110pt card and a full-screen viewer
/// without moving — and because 0043 already range-checks the same 0...1.
public struct TagPoint: Sendable, Equatable, Hashable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    /// Where this sits when the photo is drawn at `size`.
    public func point(in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
    }

    /// The inverse: a tap in a photo of `size` becomes a point on the photo.
    /// A zero-sized frame answers the centre rather than dividing by zero —
    /// a layout that has not measured yet must not place a tag at NaN.
    public static func of(_ point: CGPoint, in size: CGSize) -> TagPoint {
        guard size.width > 0, size.height > 0 else { return TagPoint(x: 0.5, y: 0.5) }
        return TagPoint(x: Double(point.x / size.width), y: Double(point.y / size.height))
    }

    /// Straight-line distance in POINTS when the photo is drawn at `size` —
    /// which is what hit-testing needs. Normalized distance would be wrong on
    /// any non-square photo: 0.05 across is a different number of points from
    /// 0.05 down.
    public func distance(to other: TagPoint, in size: CGSize) -> CGFloat {
        let mine = point(in: size)
        let theirs = other.point(in: size)
        return hypot(mine.x - theirs.x, mine.y - theirs.y)
    }
}

/// The product's category, carried so the list under a photo can be "ordered
/// by category" without a second fetch. `slug` is what `CatalogHit` returns;
/// `label` is what a human reads.
public struct TagCategory: Sendable, Equatable, Hashable, Identifiable {
    public let slug: String
    public let label: String

    public var id: String {
        slug
    }

    public init(slug: String, label: String) {
        self.slug = slug
        self.label = label
    }
}

/// One product inside a spot.
///
/// A variant, not a product: the tag names the shade you wore, which is the
/// whole point of tagging a foundation. `label` is the rendered line the
/// picker handed over ("fenty pro filt'r · 330") rather than something
/// reassembled here — the composer must not invent a shade name.
public struct TaggedProduct: Identifiable, Sendable, Equatable, Hashable {
    public let variantID: UUID
    public let label: String
    public let category: TagCategory

    public var id: UUID {
        variantID
    }

    public init(variantID: UUID, label: String, category: TagCategory) {
        self.variantID = variantID
        self.label = label
        self.category = category
    }
}

/// A tag: one spot on ONE photo, holding an ordered set of products.
///
/// `photoID` is the field the current schema has no column for, and its
/// absence is why "clicking a product tagged in a different photo scrolls to
/// that photo" is unrepresentable today rather than merely unbuilt (GLO-266).
/// It is modelled first here so the interaction can be built and tested while
/// the migration lane reshapes the table.
public struct LookTagSpot: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let photoID: UUID
    public var point: TagPoint
    /// Ordered, and unique by variant. Order is the order they were added —
    /// `look_tag_variants.position` when that lands.
    public private(set) var products: [TaggedProduct]

    public init(
        id: UUID = UUID(),
        photoID: UUID,
        point: TagPoint,
        products: [TaggedProduct] = []
    ) {
        self.id = id
        self.photoID = photoID
        self.point = point
        self.products = []
        for product in products {
            add(product)
        }
    }

    public var isEmpty: Bool {
        products.isEmpty
    }

    /// **A page indicator, not a sample size.** This counts the products in
    /// THIS spot and nothing else — no cohort, no n, no `EvidenceLine`
    /// (GLO-196). Mono at the call site, because it is a count.
    public var countLine: String? {
        products.count > 1 ? "\(products.count) products" : nil
    }

    public func holds(_ variantID: UUID) -> Bool {
        products.contains { $0.variantID == variantID }
    }

    /// Adds to the end, or moves an existing one's label into place without
    /// duplicating it. Returns whether the set grew — a caller that wants to
    /// know "was this already here?" should not have to diff the array.
    @discardableResult
    public mutating func add(_ product: TaggedProduct) -> Bool {
        if let index = products.firstIndex(where: { $0.variantID == product.variantID }) {
            products[index] = product
            return false
        }
        products.append(product)
        return true
    }

    public mutating func remove(_ variantID: UUID) {
        products.removeAll { $0.variantID == variantID }
    }
}

/// The numbers the dots are drawn at. Tokens, not literals — the dots are
/// Sean's "little dots following our design system colors", and the sizes
/// follow the same rule the colors do.
///
/// The kit has **no frame for this**: `G.Feed` draws the tagged-product list
/// (a disclosure headed `products tagged in this look · N` over card rows) but
/// nothing on the photo itself — no toggle, no dots, no overlay. So the list
/// is built to the frame and the dots are built from the design system under
/// the standing no-frames ruling, for Sean to workshop.
public enum LookTagGeometry {
    /// The dot itself. `s3` — big enough to see over a photo, small enough not
    /// to be the photo.
    public static let dotDiameter: CGFloat = Tokens.Space.s3
    /// What a tap has to land inside. The full hit target, halved to a radius,
    /// so a 12pt dot still answers a 44pt touch (the dot is drawn small; it is
    /// not *tapped* small).
    public static let dotHitRadius: CGFloat = Tokens.hitTarget / 2
    /// Two dots closer than this read as one. Placement refuses inside it
    /// rather than stacking a dot nobody can pick apart.
    public static let minimumSeparation: CGFloat = Tokens.hitTarget
}
