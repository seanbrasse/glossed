import SwiftUI
import Testing
@testable import DesignSystem

@Test func chipGlyphsCarryPolarityWithoutColor() {
    // a11y decision: polarity must survive without color (decisions log).
    #expect(Chip.Kind.like.glyph == "+")
    #expect(Chip.Kind.dislike.glyph == "\u{2212}")
    #expect(Chip.Kind.attribute.glyph == "\u{00B7}")
    #expect(Set([Chip.Kind.like.glyph, Chip.Kind.dislike.glyph, Chip.Kind.attribute.glyph]).count == 3)
}

@Test func bundledFontsExist() {
    for file in ["BricolageGrotesque", "Caveat", "SpaceMono-Regular", "SpaceMono-Bold", "SpaceMono-Italic"] {
        let url = Bundle.module.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts")
        #expect(url != nil, "missing font resource: \(file)")
    }
}

@Test func spacingScaleIsFourPointBase() {
    let scale: [CGFloat] = [
        Tokens.Space.s1, Tokens.Space.s2, Tokens.Space.s3, Tokens.Space.s4,
        Tokens.Space.s5, Tokens.Space.s6, Tokens.Space.s8, Tokens.Space.s10, Tokens.Space.s12
    ]
    #expect(scale == scale.sorted())
    #expect(scale.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
}

@Test func hitTargetMeetsMinimum() {
    #expect(Tokens.hitTarget >= 44)
}
