import SwiftUI
import Testing
@testable import DesignSystem

// The picker's pure halves: product resolution and the tone-band filter.
// Fixtures sit on both sides of every precondition (the session-12 rule).

private let oneLine = ShadeAnchorPicker.BrandEntry(
    brand: "fenty beauty",
    products: [.init(name: "pro filt'r soft matte", shades: [
        .init(code: "240", hex: .brown, tone: 6, n: 12),
        .init(code: "330", hex: .brown, tone: 9, n: 9)
    ])]
)

private let twoLines = ShadeAnchorPicker.BrandEntry(
    brand: "nars",
    products: [
        .init(name: "light reflecting", shades: [.init(code: "punjab", hex: .brown, tone: 6, n: 5)]),
        .init(name: "soft matte concealer", shades: [.init(code: "ginger", hex: .brown, tone: 6, n: 4)])
    ]
)

@Test func aNamedProductResolvesToItself() {
    let product = ShadeAnchorPicker.resolvedProduct(
        in: [oneLine, twoLines],
        selection: .init(brand: "nars", product: "soft matte concealer")
    )
    #expect(product?.name == "soft matte concealer")
}

@Test func aSingleLineBrandNeedsNoSecondQuestion() {
    let product = ShadeAnchorPicker.resolvedProduct(
        in: [oneLine, twoLines],
        selection: .init(brand: "fenty beauty")
    )
    #expect(product?.name == "pro filt'r soft matte")
}

@Test func aMultiLineBrandWithoutAChoiceAsksInsteadOfGuessing() {
    // naming one of two is worse than asking — the variant-dialog rule
    let product = ShadeAnchorPicker.resolvedProduct(
        in: [oneLine, twoLines],
        selection: .init(brand: "nars")
    )
    #expect(product == nil)
}

@Test func anUnknownBrandResolvesNothing() {
    let product = ShadeAnchorPicker.resolvedProduct(
        in: [oneLine], selection: .init(brand: "no such brand")
    )
    #expect(product == nil)
}

@Test func theBandFilterKeepsNearAndDropsFar() {
    let near = ShadeAnchorPicker.Shade(code: "a", hex: .brown, tone: 6)
    let edge = ShadeAnchorPicker.Shade(code: "b", hex: .brown, tone: 7)
    let far = ShadeAnchorPicker.Shade(code: "c", hex: .brown, tone: 9)
    #expect(ShadeAnchorPicker.isNearBand(near, toneBand: 6, band: 1))
    #expect(ShadeAnchorPicker.isNearBand(edge, toneBand: 6, band: 1))
    #expect(!ShadeAnchorPicker.isNearBand(far, toneBand: 6, band: 1))
}

@Test func absenceOfAToneIsNeverAMismatch() {
    // wrong side of the filter's precondition, both ways: no caller band,
    // and no shade tone — neither may hide a shade
    let toneless = ShadeAnchorPicker.Shade(code: "x", hex: .brown, tone: nil)
    let toned = ShadeAnchorPicker.Shade(code: "y", hex: .brown, tone: 9)
    #expect(ShadeAnchorPicker.isNearBand(toneless, toneBand: 6, band: 1))
    #expect(ShadeAnchorPicker.isNearBand(toned, toneBand: nil, band: 1))
}

@Test func notListedIsAStableWord() {
    // the quiz persists this literal as "no anchor chosen"; a rename here
    // must fail a test before it silently changes what got saved
    #expect(ShadeAnchorPicker.notListed == "not listed")
}
