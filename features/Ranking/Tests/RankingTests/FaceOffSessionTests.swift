import Foundation
import Testing
@testable import Ranking

private func session(listSize: Int) -> FaceOffSession {
    FaceOffSession(
        categoryID: UUID(),
        categoryLabel: "blushes",
        candidate: UUID(),
        rankedItemIDs: (0 ..< listSize).map { _ in UUID() }
    )
}

@Test func aSessionRecordsTheAnswerInPersistableShape() {
    var live = session(listSize: 3)
    let comparison = try? #require(live.currentComparison)
    live.record(candidateWon: true)
    #expect(live.answers.count == 1)
    #expect(live.answers[0].winnerItemID == comparison?.candidate)
    #expect(live.answers[0].loserItemID == comparison?.opponent)
    #expect(live.answers[0].skipped == false)
}

@Test func aSkipRecordsThePairButNotADirection() {
    // The pairing is data; the ordering is not. Consumers read skips out via
    // scored_face_offs, so the winner field here is arbitrary by design.
    var live = session(listSize: 4)
    live.skip()
    #expect(live.answers.count == 1)
    #expect(live.answers[0].skipped)
    #expect(live.isFinished)
}

@Test func theOutcomePlacesTheCandidateAndCarriesEveryAnswer() {
    var live = session(listSize: 3)
    while live.currentComparison != nil {
        live.record(candidateWon: false)
    }
    let outcome = live.outcome()
    #expect(outcome.orderedItemIDs.count == 4)
    #expect(outcome.comparisons.count == live.answers.count)
    #expect(!outcome.isApproximate)
}

@Test func aCappedSessionMarksItsOutcomeApproximate() {
    // Persisting a guess as though it were stated is the failure mode; the
    // outcome has to say which it is.
    var live = session(listSize: 31)
    while live.currentComparison != nil {
        live.record(candidateWon: true)
    }
    #expect(live.outcome().isApproximate)
    #expect(live.isApproximate)
}

@Test func theQuestionCountNeverExceedsTheCap() {
    // "face-off 2 of 3" makes the end visible — an open-ended run of questions
    // is how ranking starts feeling like a chore.
    for size in 1 ... 40 {
        var live = session(listSize: size)
        while live.currentComparison != nil {
            #expect(live.estimatedTotal <= RankingEngine.Insertion.maxComparisons)
            #expect(live.estimatedTotal > live.answered)
            live.record(candidateWon: size.isMultiple(of: 2))
        }
    }
}

@Test func answeringAfterTheSessionEndsChangesNothing() {
    var live = session(listSize: 3)
    while live.currentComparison != nil {
        live.record(candidateWon: true)
    }
    let settled = live
    live.record(candidateWon: false)
    live.skip()
    #expect(live == settled)
}

@Test func theFinalPositionIsOneBasedWithinTheGrownList() {
    var live = session(listSize: 4)
    while live.currentComparison != nil {
        live.record(candidateWon: true)
    }
    #expect(live.finalPosition == 1)
    #expect(live.finalListLength == 5)
}

// MARK: - Regression from the PR #32 recap

@Test func aSkippedSessionIsApproximateNotStated() {
    // A skip collapses the search range exactly as a resolved comparison does,
    // so checking bounds alone reported "I can't tell these apart" as the
    // user's stated preference — and persisted a coin-flip as evidence.
    var live = session(listSize: 4)
    live.skip()
    #expect(live.isFinished)
    #expect(live.isApproximate)
    #expect(live.outcome().isApproximate)
}

@Test func aFullyAnsweredSessionIsStatedNotApproximate() {
    var live = session(listSize: 4)
    while live.currentComparison != nil {
        live.record(candidateWon: false)
    }
    #expect(!live.isApproximate)
    #expect(!live.outcome().isApproximate)
}

@Test func aSkipAfterRealAnswersStillMarksTheOutcomeApproximate() {
    // The last question is the one that decides the placement, so a skip there
    // taints the result even when earlier answers were real.
    var live = session(listSize: 7)
    live.record(candidateWon: true)
    live.skip()
    #expect(live.outcome().isApproximate)
}
