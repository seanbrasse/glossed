import Foundation
import Testing
@testable import Looks

// The look card's media deck (GLO-235), against the kit's G.Feed frame.
// The paging rules are the frame's decisions, so they get assertions rather
// than living un-runnable inside a gesture closure.

private func photo(_ position: Int, id: UUID = UUID()) -> LookMedia {
    LookMedia(id: id, position: position, kind: .photo(.data(Data([0x89, 0x50, 0x4E, 0x47]))))
}

@Test func theDeckOrdersByPositionNotByArrivalOrder() {
    // 0043 gives no ordering guarantee on the rows; `position` does.
    let deck = LookMediaDeck([photo(2), photo(0), photo(1)])
    #expect(deck.items.map(\.position) == [0, 1, 2])
}

@Test func aPositionTieBreaksDeterministically() {
    // `unique (look_id, position)` makes this unreachable from the database,
    // but a fixture or a half-built draft can still hand over a tie — and two
    // renders of the same data must not disagree.
    let sorted = [UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
    let first = sorted[0]
    let second = sorted[1]
    let one = LookMediaDeck([photo(0, id: second), photo(0, id: first)])
    let two = LookMediaDeck([photo(0, id: first), photo(0, id: second)])
    #expect(one.items.map(\.id) == two.items.map(\.id))
    #expect(one.items.map(\.id) == [first, second])
}

@Test func depthIsCyclicTheWayTheFrameDrawsIt() {
    // The kit's (i - slide + n) % n.
    var deck = LookMediaDeck([photo(0), photo(1), photo(2)])
    #expect((0 ..< 3).map { deck.depth(of: $0) } == [0, 1, 2])
    deck.advance()
    #expect((0 ..< 3).map { deck.depth(of: $0) } == [2, 0, 1], "card 1 is now on top")
    deck.advance()
    deck.advance()
    #expect((0 ..< 3).map { deck.depth(of: $0) } == [0, 1, 2], "all the way round")
}

@Test func pagingWrapsInBothDirections() {
    var deck = LookMediaDeck([photo(0), photo(1)])
    #expect(deck.slide == 0)
    deck.goBack()
    #expect(deck.slide == 1, "back from the first card lands on the last")
    deck.advance()
    #expect(deck.slide == 0)
}

@Test func fiftyFivePointsIsTheThreshold() {
    // The frame's numbers exactly: dx < -55 advances, dx > 55 goes back, and
    // everything inside that band is a rest, not a page turn.
    #expect(LookMediaDeck.step(forDragWidth: -55.5) == .forward)
    #expect(LookMediaDeck.step(forDragWidth: -55) == .stay, "exactly 55 is not past 55")
    #expect(LookMediaDeck.step(forDragWidth: -12) == .stay)
    #expect(LookMediaDeck.step(forDragWidth: 0) == .stay)
    #expect(LookMediaDeck.step(forDragWidth: 55) == .stay)
    #expect(LookMediaDeck.step(forDragWidth: 55.5) == .back)
}

@Test func aSinglePhotoLookWearsNoPagerChrome() {
    // GLO-235's rule: one page shows no pager chrome. The kit hardcodes three
    // shots so it never met this case — its own string would have rendered
    // "added 1 photos".
    let deck = LookMediaDeck([photo(0)])
    #expect(!deck.showsChrome)
    #expect(deck.chromeLine == nil)
}

@Test func anEmptyDeckIsInertRatherThanFatal() {
    // A look with no media should not exist, but the modulo arithmetic must
    // not divide by zero on the way to finding that out.
    var deck = LookMediaDeck([])
    #expect(deck.isEmpty)
    #expect(deck.chromeLine == nil)
    #expect(deck.depth(of: 0) == 0)
    deck.advance()
    deck.goBack()
    #expect(deck.slide == 0)
}

@Test func theChromeLineCountsThisPostsPhotosAndMakesNoClaim() {
    // A look post is attributed content, never a claim (GLO-196). The only
    // number on it counts the post's own photos — no n, no cohort, nothing
    // that could be read as a sample size. This test fails the day someone
    // makes it "3 of 6 · n=12".
    let deck = LookMediaDeck([photo(0), photo(1), photo(2)])
    #expect(deck.chromeLine == "added 3 photos", "the frame's own copy")
    let line = deck.chromeLine ?? ""
    #expect(!line.contains("n="))
    #expect(!line.contains(" of "))
    #expect(line == line.lowercased(), "lowercase UI copy")
}

@Test func theSlideSurvivesReorderingBecauseOrderIsPositionNotArrival() {
    // GLO-232 lets the composer move photos; the card reads `position` and
    // does not care who set it. Same positions in, same deck out.
    let ids = (0 ..< 3).map { _ in UUID() }
    let asComposed = LookMediaDeck([
        photo(0, id: ids[0]), photo(1, id: ids[1]), photo(2, id: ids[2])
    ])
    let afterAReorder = LookMediaDeck([
        photo(2, id: ids[0]), photo(0, id: ids[1]), photo(1, id: ids[2])
    ])
    #expect(asComposed.items.map(\.id) == [ids[0], ids[1], ids[2]])
    #expect(afterAReorder.items.map(\.id) == [ids[1], ids[2], ids[0]])
}

@Test func theSeamIsTheKindNotTheDeck() {
    // The deck orders, pages and labels in terms of LookMedia. Nothing in it
    // reads `.photo`, which is what makes a second kind a change to the page
    // view alone (GLO-234, deferred — the seam is kept, not the feature).
    let deck = LookMediaDeck([photo(1), photo(0)])
    #expect(deck.count == 2)
    #expect(deck.chromeLine == "added 2 photos")
    for item in deck.items {
        guard case .photo = item.kind else {
            Issue.record("fixture should be photos")
            return
        }
    }
}
