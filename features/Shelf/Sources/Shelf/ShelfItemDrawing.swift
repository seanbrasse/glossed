import DesignSystem
import Foundation

// How a shelf item is drawn: its height on the shelf and the width it packs
// at. Split from ShelfItem.swift for the 300-line ceiling when the volume
// estimate landed — a mechanical move, nothing renamed.

public extension ShelfItem {
    /// How tall to draw this object, in `ProductMock`'s scale units.
    ///
    /// **The ratios are compressed, and the name says drawn rather than real.**
    /// A 15mm compact next to a 190mm shampoo bottle is a 12× difference; drawn
    /// at 12× either the compact is four points tall or the bottle does not fit
    /// in an 82pt bay. So real millimetres are mapped linearly onto the band the
    /// kit draws in and clamped at both ends. What survives is the ordering and
    /// a visible difference — which is what PRD §08 asks for ("a lipstick is
    /// visibly smaller than a shampoo bottle") — not the true proportion.
    ///
    /// With no measurement, the kit's own per-kind table stands in. It is not a
    /// guess dressed as data: a bottle is drawn taller than a compact because
    /// bottles are taller than compacts, and nothing about the individual
    /// product is being claimed.
    var drawnScale: CGFloat {
        if let heightMM, heightMM > 0 {
            return ShelfItem.scale(forHeightMM: heightMM)
        }
        // No measured height, but a volume: containers scale roughly
        // isometrically, so height goes as the cube root of volume. The
        // factor puts a 30ml foundation near 78mm and a 236ml pump near
        // 155mm — the pump towers, which is the §08 point. An estimate,
        // and only ordering is claimed for it; the band clamps the rest.
        if let sizeML, sizeML > 0 {
            return ShelfItem.scale(forHeightMM: 25 * cbrt(sizeML))
        }
        return ShelfItem.kitScale(packaging)
    }

    /// Real (or estimated) millimetres onto the kit's drawing band — see the
    /// `drawnScale` doc for why the ratios are compressed.
    static func scale(forHeightMM heightMM: Double) -> CGFloat {
        let clamped = min(max(heightMM, ShelfItem.shortestMM), ShelfItem.tallestMM)
        let fraction = (clamped - ShelfItem.shortestMM) / (ShelfItem.tallestMM - ShelfItem.shortestMM)
        return ShelfItem.smallestScale + CGFloat(fraction) * (ShelfItem.largestScale - ShelfItem.smallestScale)
    }

    /// A pressed powder compact and a litre shampoo bottle — the ends of what a
    /// beauty shelf actually holds. Outside these the drawing stops changing,
    /// which is better than a travel sample vanishing.
    static let shortestMM: Double = 15
    static let tallestMM: Double = 200

    /// The band the kit draws in, taken from its own per-kind table: nothing is
    /// smaller than a compact and nothing is much taller than a bottle.
    static let smallestScale: CGFloat = 44
    static let largestScale: CGFloat = 88

    /// How much shelf this object takes up: what it draws, or the floor that
    /// keeps its rank sticker off its neighbour's — whichever is larger.
    ///
    /// Both the packing and the layout use this. They have to be the same
    /// number: pack by the slot and render at the drawn width and the shelf
    /// comes out short of full, with the stickers back where they started.
    ///
    /// A photo's drawn width is its aspect at the drawn height; a mock's is
    /// its silhouette's. The pack must use whichever will actually render, or
    /// the stickers collide again (GLO-68).
    var slotWidth: CGFloat {
        let drawn: CGFloat = if let catalogImageAspect {
            drawnScale * CGFloat(catalogImageAspect)
        } else {
            ProductMock.drawnWidth(kind: packaging, scale: drawnScale)
        }
        return max(drawn, ShelfBay.minimumSlot)
    }

    /// `kindH` in `G.Shelf`.
    static func kitScale(_ packaging: ProductMock.Kind) -> CGFloat {
        switch packaging {
        case .compact: 44
        case .jar: 50
        case .tube: 62
        case .mist: 66
        case .dropper: 68
        case .bottle: 74
        }
    }
}
