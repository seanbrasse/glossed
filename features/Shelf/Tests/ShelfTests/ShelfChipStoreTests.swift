import DataKit
import Foundation
import Testing
@testable import Shelf

// GLO-16: the chip editor's live path. The factory itself needs a client and
// is proven by driving, but the two decisions it makes on the way through are
// ordinary values and belong in a test — they are the places a wrong answer
// would be invisible rather than loud.

@Test func aVocabularyChipKeepsItsValenceAcrossTheEdge() {
    // A dislike that arrived as a like would aggregate in the wrong direction
    // for everyone, quietly. The mapping is case-by-case so a new valence is
    // a compile error rather than a silent default.
    let liked = ExperienceChip(
        id: UUID(),
        domain: .makeup,
        categoryID: nil,
        slug: "lasted-all-day",
        label: "lasted all day",
        valence: .like
    )
    let disliked = ExperienceChip(
        id: UUID(),
        domain: .skincare,
        categoryID: UUID(),
        slug: "broke-me-out",
        label: "broke me out",
        valence: .dislike
    )

    #expect(ShelfChip(liked).valence == .like)
    #expect(ShelfChip(disliked).valence == .dislike)
    #expect(ShelfChip(liked).id == liked.id)
    #expect(ShelfChip(disliked).label == "broke me out")
}

private func category(_ slug: String) -> (slug: String, id: UUID) {
    (slug: slug, id: UUID())
}

@Test func aKnownSlugNarrowsTheVocabularyToItsCategory() {
    // The shelf carries a slug and the core wants an id. This lookup is the
    // whole of that translation, and driving cannot check it: the seed has
    // ten domain-wide chips and no category-scoped ones, so a shelf with the
    // narrowing broken looks exactly like one with it working.
    let foundation = category("foundation")
    let all = [category("blush"), foundation, category("concealer")]

    #expect(ShelfChipStore.categoryID(forSlug: "foundation", in: all) == foundation.id)
}

@Test func anUnknownSlugCostsTheNarrowingAndNotTheEditor() {
    // Degrading to the domain-wide chips is the point: an unrecognised
    // category should lose you "oxidized on me", not the whole chip section.
    #expect(ShelfChipStore.categoryID(forSlug: "not-a-category", in: [category("blush")]) == nil)
    #expect(ShelfChipStore.categoryID(forSlug: "blush", in: []) == nil)
}

@Test func anEmptiedNoteClearsTheColumnRatherThanStoringNothing() {
    // `""` and NULL read the same to a person and differently to every query
    // asking whether a note exists. Deleting your note should mean there is
    // no note.
    #expect(ShelfChipStore.storedNote(from: "") == nil)
    #expect(ShelfChipStore.storedNote(from: "   ") == nil)
    #expect(ShelfChipStore.storedNote(from: "\n\t ") == nil)
}

@Test func arealNoteSurvivesWithItsOwnWordsIntact() {
    #expect(ShelfChipStore.storedNote(from: "pills under spf") == "pills under spf")
    // Trimmed at the edges, untouched inside — a note is prose, not a token.
    #expect(ShelfChipStore.storedNote(from: "  two  spaces inside  ") == "two  spaces inside")
}
