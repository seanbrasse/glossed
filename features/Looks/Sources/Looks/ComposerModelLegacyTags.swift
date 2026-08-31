import CoreGraphics
import Foundation

// The legacy seam, in its own file so its deletion is one `git rm` (GLO-266).
//
// Everything here exists because `look_tags` is still the 0043 shape —
// look-scoped, one product per row. Migration 0049 replaces that shape with
// spots on photos; when it lands and the save path takes spots, this file is
// DELETED, not fixed. It is also what pushed `ComposerModel` past the 300-line
// ceiling after the #412/#420 merge, which is the same extraction remedy
// `AppShellLadder` set the precedent for.

public extension ComposerModel {
    /// What the save can carry TODAY, projected down from the board.
    ///
    /// **The gap is visible right here.** `look_tags` is `(look_id,
    /// variant_id, x, y)` — look-scoped, one product per row — so this
    /// projection drops *which photo* on the floor and splits a spot holding
    /// three products into three rows at the same coordinates. That is
    /// GLO-266's finding, made concrete at the exact line where it costs
    /// something. When the migration lands, `save` takes spots and this
    /// projection is deleted rather than fixed.
    var tags: [ComposerTag] {
        tagBoard.spots.flatMap { spot in
            spot.products.map {
                ComposerTag(variantID: $0.variantID, label: $0.label, x: spot.point.x, y: spot.point.y)
            }
        }
    }

    /// The one-shot path that predates the board: tag a product without
    /// choosing a spot. It places on the FIRST photo, which is what a
    /// look-scoped tag always silently meant.
    ///
    /// Kept because the debug catalog still calls it, and because a caller
    /// with no category cannot build a `TaggedProduct` — hence
    /// `TagCategory.unknown`. It retires with that fixture.
    func tag(_ candidate: ShelfTagCandidate, x: Double, y: Double) {
        guard let first = photos.first else { return }
        let point = TagPoint(x: x, y: y)
        // A notional frame, because this path has no rendered size to offer.
        // Big enough that two genuinely different pins get their own spots and
        // two near-identical ones merge — which is the rule the tappable
        // canvas applies against a real frame.
        let frame = CGSize(width: 1000, height: 1000)
        let crowded = tagBoard.spot(
            at: point.point(in: frame),
            in: frame,
            on: first.id,
            radius: LookTagGeometry.minimumSeparation
        )
        guard let spotID = tagBoard.place(on: first.id, at: point, in: frame) ?? crowded?.id else {
            return
        }
        tagBoard.add(
            TaggedProduct(variantID: candidate.variantID, label: candidate.label, category: .unknown),
            to: spotID
        )
    }
}
