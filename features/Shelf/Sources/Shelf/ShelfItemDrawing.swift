import DesignSystem
import Foundation

// How a shelf item is drawn: its size class, the height that class draws at,
// and the width it packs at. Split from ShelfItem.swift for the 300-line
// ceiling when the volume estimate landed — a mechanical move at the time;
// GLO-82 then replaced the continuous scale with three buckets.

/// Small, medium, large — the whole sizing vocabulary (GLO-82, Sean's call:
/// "lump things into a small medium large size").
///
/// Three buckets instead of a continuous scale: a shelf where every object
/// stands at its own millimetre reads as noise, and the estimates behind
/// those millimetres were never better than a kind and a volume anyway.
/// What survives is the §08 ordering — a lipstick is visibly smaller than a
/// shampoo bottle — said in three sizes a shelf can actually hold.
public enum ShelfSizeClass: CaseIterable, Sendable {
    case small, medium, large

    /// Drawn height, in `ProductMock`'s scale units. Inside the kit's band.
    ///
    /// Capped so nothing can reach the category label (GLO-149, Sean's call:
    /// words above the images, images kept to a size that cannot overlap
    /// them). The three were 44 / 60 / 78, which put a `large` item's top 1pt
    /// below the bay's own top and straight through the label.
    ///
    /// Three constraints meet in these numbers and only one of them is the
    /// label, which is why they are not a simple scale-down:
    ///
    /// 1. **The label band.** Nothing may draw taller than what the bay has
    ///    left once the words have their room — `ShelfBayView.itemHeightCap`.
    /// 2. **The packing floor.** A `small` item's slot is its drawn width,
    ///    `height × 0.8`. Shrink it and compacts pack the same number per bay
    ///    as tubes do — a size class that still exists in the type system and
    ///    no longer exists on screen. An existing test caught exactly this on
    ///    the first attempt at the cap; it puts `small` above 40.3.
    /// 3. **The kit's 1.5× distinction.** `large` reads as more than half
    ///    again the height of `small`, so it must clear 63.
    ///
    /// 42 / 54 / 66 is the smallest set satisfying all three, which is what
    /// keeps the bay's growth to 5pt instead of the ~19 that reserving the
    /// band without a cap would have cost. A test holds each constraint.
    public var height: CGFloat {
        switch self {
        case .small: 42
        case .medium: 54
        case .large: 66
        }
    }

    /// The widest this class may draw or pack. The large cap is derived from
    /// the shelf's own guarantee — see `ShelfSizeClass.largesPerShelf` — and
    /// the others step down so the classes stay visibly distinct.
    public var maxWidth: CGFloat {
        switch self {
        case .small: 44
        case .medium: 56
        case .large: 70
        }
    }

    /// The guarantee the large cap is derived from: at least this many large
    /// items fit one bay, padding and all, on the narrowest shelf we draw
    /// (a 375pt screen: 375 − 32 page − 28 bay padding = 315 inside).
    /// 4×70 + 3×10 gaps = 310 ≤ 315. A test holds the arithmetic.
    public static let largesPerShelf = 4
    public static let narrowestBayWidth: CGFloat = 315
}

public extension ShelfItem {
    /// Which bucket this object belongs to.
    ///
    /// A measured `height_mm` decides directly — a real ruler beats every
    /// table. A volume estimates height by the cube root (containers scale
    /// roughly isometrically), clamped into the silhouette's plausible range
    /// first: the cube root alone sends a 30ml compact and a 30ml dropper to
    /// the same 78mm, and neither is 78mm. No data falls back to the kind —
    /// a bottle is large and a compact is small because bottles are taller
    /// than compacts, and nothing about the individual product is claimed.
    var sizeClass: ShelfSizeClass {
        if let heightMM, heightMM > 0 {
            return ShelfItem.sizeClass(forHeightMM: heightMM)
        }
        if let sizeML, sizeML > 0 {
            let range = ShelfItem.plausibleMM(packaging)
            let estimated = min(max(25 * cbrt(sizeML), range.lowerBound), range.upperBound)
            return ShelfItem.sizeClass(forHeightMM: estimated)
        }
        return ShelfItem.kitSizeClass(packaging)
    }

    /// Millimetres into a bucket. The thresholds split the plausible ranges:
    /// travel and palette territory below 60, full-size bottles above 115.
    static func sizeClass(forHeightMM heightMM: Double) -> ShelfSizeClass {
        switch heightMM {
        case ..<60: .small
        case ..<115: .medium
        default: .large
        }
    }

    /// What each silhouette actually stands at, in millimetres — the range a
    /// volume estimate may land in. Measured `height_mm` is never clamped by
    /// kind: a real ruler beats this table.
    static func plausibleMM(_ packaging: ProductMock.Kind) -> ClosedRange<Double> {
        switch packaging {
        case .compact: 15 ... 40
        case .jar: 45 ... 90
        case .tube: 80 ... 160
        case .dropper: 85 ... 140
        case .bottle: 100 ... 200
        case .mist: 110 ... 200
        }
    }

    /// The kind's own bucket, for a row with no measurement and no volume.
    static func kitSizeClass(_ packaging: ProductMock.Kind) -> ShelfSizeClass {
        switch packaging {
        case .compact, .jar: .small
        case .tube, .dropper: .medium
        case .bottle, .mist: .large
        }
    }

    /// How tall to draw this object — its bucket's height.
    var drawnScale: CGFloat {
        sizeClass.height
    }

    /// How much shelf this object takes up: what it draws — capped at its
    /// bucket's width, which is also what `ProductImage` renders it at — or
    /// the floor that keeps its rank sticker off its neighbour's, whichever
    /// is larger. Packing and rendering must be the same number (GLO-68).
    var slotWidth: CGFloat {
        let drawn: CGFloat = if let catalogImageAspect {
            drawnScale * min(CGFloat(catalogImageAspect), ProductImage.maxPhotoAspect)
        } else {
            ProductMock.drawnWidth(kind: packaging, scale: drawnScale)
        }
        return min(max(drawn, ShelfBay.minimumSlot), sizeClass.maxWidth)
    }
}
