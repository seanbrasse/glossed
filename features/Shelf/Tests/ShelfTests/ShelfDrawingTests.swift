import DataKit
import DesignSystem
import Foundation
import Testing
@testable import Shelf

// GLO-82: sizes are three buckets — small, medium, large — with limits the
// slot and the render agree on, and a guarantee the large cap is derived
// from: four larges fit one shelf, padding and all.

private func drawn(
    packaging: ProductMock.Kind,
    heightMM: Double? = nil,
    sizeML: Double? = nil,
    aspect: Double? = nil
) -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: "b",
        name: "n",
        categorySlug: "c",
        categoryLabel: "c",
        domain: .makeup,
        packaging: packaging,
        heightMM: heightMM,
        sizeML: sizeML,
        catalogImageAspect: aspect
    )
}

struct ShelfDrawingTests {
    @Test func fourLargeThingsFitOneShelfPaddingAndAll() {
        // Sean's floor, held as arithmetic against the packing's own
        // constants: the widest possible large slots, the real gap, the
        // narrowest bay we draw.
        let larges = CGFloat(ShelfSizeClass.largesPerShelf)
        let needed = larges * ShelfSizeClass.large.maxWidth
            + (larges - 1) * ShelfBay.itemGap
        #expect(needed <= ShelfSizeClass.narrowestBayWidth)

        // And the packing agrees: four max-width larges land in one bay.
        let wide = (0 ..< ShelfSizeClass.largesPerShelf).map { _ in
            drawn(packaging: .bottle, sizeML: 236, aspect: 2.0)
        }
        let bays = ShelfBay.chunks(of: wide, fittingWidth: ShelfSizeClass.narrowestBayWidth)
        #expect(bays.count == 1)
    }

    @Test func theVolumeEstimateRespectsTheSilhouette() {
        // The cube root alone sends both 30ml containers to the same 78mm.
        // A compact is squat whatever its volume says: it lands small, and
        // the bottle lands in a taller bucket.
        let compact = drawn(packaging: .compact, sizeML: 30)
        let bottle = drawn(packaging: .bottle, sizeML: 30)
        #expect(compact.sizeClass == .small)
        #expect(compact.drawnScale < bottle.drawnScale)
    }

    @Test func aMeasuredHeightIsNeverSecondGuessedByKind() {
        // A real ruler beats the plausibility table: a genuinely tall
        // compact (a stacked palette) buckets by its measurement even
        // though the compact range tops out at 40mm.
        let measured = drawn(packaging: .compact, heightMM: 150, sizeML: 30)
        #expect(measured.sizeClass == .large)
    }

    @Test func aWidePhotoPacksAtItsBucketsCapNotTheCarton() {
        // The slot reserves what ProductImage renders: the bucket's cap.
        let carton = drawn(packaging: .bottle, sizeML: 30, aspect: 2.0)
        #expect(carton.slotWidth == carton.sizeClass.maxWidth)

        // A photo inside the cap still packs at its own width.
        let slim = drawn(packaging: .bottle, sizeML: 236, aspect: 0.6)
        #expect(slim.slotWidth == slim.drawnScale * 0.6)
    }

    @Test func everyInputLandsInABucket() {
        for kind in [ProductMock.Kind.compact, .jar, .tube, .dropper, .bottle, .mist] {
            for ml in [1.0, 30, 236, 1000] {
                let item = drawn(packaging: kind, sizeML: ml)
                #expect(ShelfSizeClass.allCases.contains(item.sizeClass))
                #expect(item.slotWidth <= item.sizeClass.maxWidth)
                #expect(item.slotWidth >= ShelfBay.minimumSlot)
            }
        }
    }
}
