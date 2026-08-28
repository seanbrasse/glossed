import Foundation
import Testing
@testable import Ranking

private func ids(_ count: Int) -> [UUID] {
    (0 ..< count).map { _ in UUID() }
}

@Test func insertionConvergesWithinTheComparisonCap() {
    // Fifteen items is the largest list that fully resolves in four questions.
    for size in 1 ... 15 {
        let list = ids(size)
        var insertion = RankingEngine.Insertion(candidate: UUID(), list: list)
        var asked = 0
        while let comparison = insertion.nextComparison {
            // Always prefer the incumbent, so the candidate walks to the end.
            _ = comparison
            insertion.record(candidateWon: false)
            asked += 1
        }
        #expect(asked <= RankingEngine.Insertion.maxComparisons)
        #expect(insertion.result().count == size + 1)
    }
}

@Test func aWinnerLandsAboveTheItemItBeat() {
    let list = ids(5)
    let candidate = UUID()
    var insertion = RankingEngine.Insertion(candidate: candidate, list: list)
    while insertion.nextComparison != nil {
        insertion.record(candidateWon: true)
    }
    #expect(insertion.result().first == candidate)
}

@Test func aLoserLandsLast() {
    let list = ids(4)
    let candidate = UUID()
    var insertion = RankingEngine.Insertion(candidate: candidate, list: list)
    while insertion.nextComparison != nil {
        insertion.record(candidateWon: false)
    }
    #expect(insertion.result().last == candidate)
}

@Test func skipSettlesWithoutExpressingAPreference() {
    let list = ids(4)
    let candidate = UUID()
    var insertion = RankingEngine.Insertion(candidate: candidate, list: list)
    insertion.skip()
    // A skip ends the insertion rather than nudging the candidate either way.
    #expect(insertion.isSettled)
    let result = insertion.result()
    #expect(result.count == 5)
    #expect(result.firstIndex(of: candidate) == 2)
}

@Test func aThreeItemListResolvesInTwoQuestions() {
    // The unlock threshold: the first ranking someone ever does must be short.
    var insertion = RankingEngine.Insertion(candidate: UUID(), list: ids(3))
    var asked = 0
    while insertion.nextComparison != nil {
        insertion.record(candidateWon: asked == 0)
        asked += 1
    }
    #expect(asked == 2)
}

@Test func aContradictionMovesOnlyWhatItMust() {
    let list = ids(5)
    // #4 beats #2: the winner lifts to just above the loser, and nothing else
    // in a list the user built over weeks gets reshuffled.
    let next = RankingEngine.applying(winner: list[3], over: list[1], to: list)
    #expect(next == [list[0], list[3], list[1], list[2], list[4]])
}

@Test func aResultConsistentWithTheListChangesNothing() {
    let list = ids(5)
    #expect(RankingEngine.applying(winner: list[1], over: list[3], to: list) == list)
}

private let day: TimeInterval = 86400
private let start = Date(timeIntervalSince1970: 1_700_000_000)

@Test func immediateCategoriesNeverWait() {
    // Sunscreen and cleanser are judged the day you use them.
    #expect(RankingRules.isPastWearIn(startedOn: nil, wearInDays: 0))
    #expect(RankingRules.isPastWearIn(startedOn: start, wearInDays: 0, now: start))
}

@Test func wearInHoldsUntilTheWindowElapses() {
    // Actives at 56 days: a verdict at week one is a verdict about nothing.
    #expect(!RankingRules.isPastWearIn(startedOn: start, wearInDays: 56, now: start + 7 * day))
    #expect(!RankingRules.isPastWearIn(startedOn: start, wearInDays: 56, now: start + 55 * day))
    #expect(RankingRules.isPastWearIn(startedOn: start, wearInDays: 56, now: start + 56 * day))
}

@Test func aMissingStartDateKeepsAWearInItemOut() {
    // We cannot vouch for a window we have no start for, so it stays ineligible
    // rather than quietly counting.
    #expect(!RankingRules.isPastWearIn(startedOn: nil, wearInDays: 14))
}

@Test func remainingDaysDriveTheNudge() {
    #expect(RankingRules.daysUntilRankable(startedOn: start, wearInDays: 14, now: start) == 14)
    #expect(RankingRules.daysUntilRankable(startedOn: start, wearInDays: 14, now: start + 13 * day) == 1)
    #expect(RankingRules.daysUntilRankable(startedOn: start, wearInDays: 14, now: start + 30 * day) == 0)
}

@Test func rankingUnlocksAtThree() {
    #expect(!RankingRules.isUnlocked(eligibleItemCount: 2))
    #expect(RankingRules.isUnlocked(eligibleItemCount: 3))
}

@Test func percentileRunsFromFirstToLast() {
    #expect(RankingRules.percentile(position: 1, listLength: 5) == 1.0)
    #expect(RankingRules.percentile(position: 5, listLength: 5) == 0.0)
    #expect(RankingRules.percentile(position: 3, listLength: 5) == 0.5)
}

@Test func aSingleItemListContributesNothing() {
    // Being the only blush you own is not evidence that it is a good blush.
    // Scoring it 1.0 would let one-item shelves dominate every leaderboard.
    #expect(RankingRules.percentile(position: 1, listLength: 1) == nil)
}

@Test func percentileRejectsPositionsOutsideTheList() {
    #expect(RankingRules.percentile(position: 0, listLength: 5) == nil)
    #expect(RankingRules.percentile(position: 6, listLength: 5) == nil)
}

// MARK: - Regressions from the PR #30 recap

@Test func aCappedPlacementIsMarkedAsAGuess() {
    // Thirty-one items with the candidate winning every time halves the range
    // down to two and runs out of questions. The caller has to tell that
    // placement apart from a stated one, or it persists a guess as though the
    // user said it.
    var insertion = RankingEngine.Insertion(candidate: UUID(), list: ids(31))
    while insertion.nextComparison != nil {
        insertion.record(candidateWon: true)
    }
    #expect(insertion.isSettled)
    #expect(insertion.wasCapped)
    #expect(!insertion.isExact)
}

@Test func aResolvedPlacementIsExact() {
    var insertion = RankingEngine.Insertion(candidate: UUID(), list: ids(4))
    while insertion.nextComparison != nil {
        insertion.record(candidateWon: false)
    }
    #expect(insertion.isExact)
    #expect(!insertion.wasCapped)
}

@Test func answeringPastTheCapChangesNothing() {
    // A caller that ignores nextComparison must not be able to push the search
    // past the four questions the design allows.
    var insertion = RankingEngine.Insertion(candidate: UUID(), list: ids(16))
    while insertion.nextComparison != nil {
        insertion.record(candidateWon: false)
    }
    let settled = insertion
    insertion.record(candidateWon: true)
    insertion.skip()
    #expect(insertion == settled)
}

@Test func anItemWaitingOnAStartDateIsNamedNotJustNil() {
    // The item most stuck is the one with no countdown to show, so it gets a
    // state of its own rather than a bare nil the UI has to guess at.
    #expect(RankingRules.isBlockedPendingStartDate(startedOn: nil, wearInDays: 56))
    #expect(RankingRules.daysUntilRankable(startedOn: nil, wearInDays: 56) == nil)
    #expect(!RankingRules.isBlockedPendingStartDate(startedOn: nil, wearInDays: 0))
    #expect(RankingRules.daysUntilRankable(startedOn: nil, wearInDays: 0) == 0)
}
