import DataKit
import Foundation
import Testing
@testable import AddLadder

// Its own file for the reason this codebase keeps meeting: `NearMatchRungModelTests`
// sits at SwiftLint's 300-line ceiling, the same wall `ShelfModel`, `ScreenEntries`
// and `ScreenData` have all hit. Splitting is the established answer.
//
// GLO-179: the rung's failure hint says "try again", so something has to be
// pressable. These pin `failure` — the exact condition the button is gated on
// — because the button itself lives in the view, and this package tests models.

/// Fails the first call and succeeds after, so a *retry* can be told apart from
/// a first attempt. `FakeNearMatching` is all-or-nothing by design and cannot.
actor FlakyNearMatching: NearMatching {
    private let matches: [NearMatch]
    private(set) var calls = 0

    init(matches: [NearMatch]) {
        self.matches = matches
    }

    func nearMatches(
        _: String, domain _: Domain?, gtin _: String?
    ) async throws(GlossedError) -> [NearMatch] {
        calls += 1
        if calls == 1 {
            throw GlossedError(.offline, userMessage: "no connection — try again in a sec.")
        }
        return matches
    }
}

@MainActor
@Test func aFailedNearMatchLookupCanBeRetriedIntoAnAnswer() async throws {
    let catalog = try FlakyNearMatching(matches: [
        nearMatch(name: "lip sleeping mask", why: "similar name — check the shade and size")
    ])
    let live = NearMatchRungModel(
        catalog: catalog, ladder: Ladder(entry: .nearMatches, query: "laneige")
    )

    await live.search()
    #expect(live.failure != nil)
    #expect(!live.isCandidateListTrustworthy, "an unanswered list never vouches for itself")

    await live.search()
    #expect(live.failure == nil)
    #expect(await catalog.calls == 2, "a retry is a second ask, not a replayed answer")
    #expect(live.isCandidateListTrustworthy)
}

@MainActor
@Test func theFailureOutlivesTheRetryItStarted() async throws {
    // Unlike the search rung, this one clears `failure` only when an answer
    // arrives — a window with no error and no candidates would read as
    // "nothing matched, safe to create". That is why the button is disabled
    // while searching rather than removed: it is still on screen mid-retry.
    let catalog = try FlakyNearMatching(matches: [
        nearMatch(name: "lip sleeping mask", why: "similar name")
    ])
    let live = NearMatchRungModel(
        catalog: catalog, ladder: Ladder(entry: .nearMatches, query: "laneige")
    )
    await live.search()

    let failureBefore = live.failure
    #expect(failureBefore != nil)
    // Nothing clears it on the way in — only a landed answer does.
    #expect(live.failure?.userMessage == failureBefore?.userMessage)
}
