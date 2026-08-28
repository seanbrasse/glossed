import Foundation
import Testing
@testable import AddLadder

@Test func theRailShowsTheWholeLadderNotJustWhereYouHaveBeen() {
    // The kit renders four segments from the first rung onward. A breadcrumb of
    // visited rungs — which is what this used to be — hides how much is left,
    // which is the one question the rail exists to answer.
    #expect(LadderRail.railRungs == [.search, .barcode, .nearMatches, .create])
}

@Test func everyRailSegmentIsNamed() {
    for rung in LadderRail.railRungs {
        #expect(!LadderRail.label(for: rung).isEmpty)
    }
    #expect(LadderRail.label(for: .nearMatches) == "near matches")
    #expect(LadderRail.label(for: .create) == "create it")
    #expect(LadderRail.label(for: .barcode) == "scan")
}

@Test func fillRunsUpToAndIncludingTheCurrentRung() {
    #expect(LadderRail.isFilled(0, at: .search))
    #expect(LadderRail.isFilled(1, at: .search) == false)

    #expect(LadderRail.isFilled(0, at: .nearMatches))
    #expect(LadderRail.isFilled(1, at: .nearMatches))
    #expect(LadderRail.isFilled(2, at: .nearMatches))
    #expect(LadderRail.isFilled(3, at: .nearMatches) == false)
}

@Test func confirmLeavesTheLastSegmentCurrentRatherThanFallingOffTheEnd() {
    // `confirm` is not a rail rung. It must not read as "no segment is current",
    // which is what an unclamped lookup would produce.
    #expect(LadderRail.position(of: .confirm) == LadderRail.railRungs.count - 1)
    #expect(LadderRail.label(for: .confirm) == "create it")
    for segment in LadderRail.railRungs.indices {
        #expect(LadderRail.isFilled(segment, at: .confirm))
    }
}

@Test func everyRungHasAPositionOnTheRail() {
    // Including the one that is not on it — nothing may fall through.
    for rung in Rung.allCases {
        let position = LadderRail.position(of: rung)
        #expect(LadderRail.railRungs.indices.contains(position))
    }
}

@Test func theRailAdvancesAsTheLadderDoes() {
    var ladder = Ladder()
    #expect(LadderRail.position(of: ladder.rung) == 0)
    ladder.noneOfThese()
    #expect(LadderRail.position(of: ladder.rung) == 1)
    ladder.noneOfThese()
    #expect(LadderRail.position(of: ladder.rung) == 2)
    ladder.noneOfThese()
    #expect(LadderRail.position(of: ladder.rung) == 3)
}
