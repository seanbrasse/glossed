import Testing
@testable import Collections

// The tint's wire words are what land in `collections.cover_tint`, so they
// are pinned here rather than left to a rename to quietly change.

@Test func theFourTintsAreTheKitsFourCoversInTheKitsOrder() {
    #expect(CollectionTint.allCases.map(\.rawValue) == ["butter", "cherry", "mint", "lilac"])
}

@Test func aTintsLabelIsItsWireWordLowercase() {
    #expect(CollectionTint.allCases.allSatisfy { $0.label == $0.rawValue })
    #expect(CollectionTint.allCases.allSatisfy { $0.label == $0.label.lowercased() })
}

@Test func parseAcceptsTheWireWordsAndRefusesEverythingElse() {
    #expect(CollectionTint.parse("mint") == .mint)
    // A colour nobody drew is nil, not a silent butter — the grid then draws
    // a plain card rather than inventing a choice the user never made.
    #expect(CollectionTint.parse("chartreuse") == nil)
    // The kit's CSS variable is NOT the wire word. Storing `var(--mint-soft)`
    // in a text column is how a stylesheet ends up in a database.
    #expect(CollectionTint.parse("var(--mint-soft)") == nil)
    // The column is nullable, and nil is an ordinary answer.
    #expect(CollectionTint.parse(nil) == nil)
}
