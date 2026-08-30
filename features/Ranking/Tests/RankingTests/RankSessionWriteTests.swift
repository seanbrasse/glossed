import DataKit
import Foundation
import Testing
@testable import Ranking

// What crosses the boundary when a session ends: every comparison, the whole
// ordering, and — when the write does not land — no celebration. Fixtures are
// shared with `RankSessionModelTests`.

// MARK: - the write

@MainActor
@Test func finishingWritesEveryComparisonAndTheWholeOrdering() async throws {
    let candidate = UUID()
    let applied = Applied()
    let model = try await loaded(RankSessionModel(
        userItemID: candidate,
        store: store(
            shelf: [row(id: candidate), row(rank: 1), row(rank: 2)],
            categories: [category()],
            applied: applied
        )
    ))
    guard case var .ready(session) = model.state else {
        Issue.record("three eligible items unlock the category")
        return
    }
    while session.currentComparison != nil {
        session.record(candidateWon: false)
    }

    model.finish(session.outcome())
    await model.saveTask?.value

    let positions = await applied.positions
    let faceOffs = await applied.faceOffs
    #expect(positions.count == 3, "the RPC rebuilds the whole ordering, not just the new row")
    #expect(positions.map(\.position) == [1, 2, 3], "positions are 1-based and contiguous")
    #expect(positions.last?.userItemID == candidate, "losing every face-off places it last")
    #expect(faceOffs.count == session.answers.count)
    #expect(model.saveFailure == nil)
}

@MainActor
@Test func aSkipCrossesTheBoundaryStillMarkedAsASkip() async throws {
    // The pair is data; the direction is not. `scored_face_offs` drops skips,
    // and it can only do that if the flag survives the translation.
    let candidate = UUID()
    let applied = Applied()
    let model = try await loaded(RankSessionModel(
        userItemID: candidate,
        store: store(
            shelf: [row(id: candidate), row(rank: 1), row(rank: 2)],
            categories: [category()],
            applied: applied
        )
    ))
    guard case var .ready(session) = model.state else {
        Issue.record("three eligible items unlock the category")
        return
    }
    session.skip()

    model.finish(session.outcome())
    await model.saveTask?.value

    let faceOffs = await applied.faceOffs
    #expect(faceOffs.count == 1)
    #expect(faceOffs.first?.skipped == true)
}

@MainActor
@Test func aFailedWriteIsSaidOutLoudRatherThanCelebrated() async throws {
    let candidate = UUID()
    let model = try await loaded(RankSessionModel(
        userItemID: candidate,
        store: store(
            shelf: [row(id: candidate), row(rank: 1), row(rank: 2)],
            categories: [category()],
            failingApply: true
        )
    ))
    guard case let .ready(session) = model.state else {
        Issue.record("three eligible items unlock the category")
        return
    }

    model.finish(session.outcome())
    await model.saveTask?.value

    #expect(model.saveFailure == "the connection dropped")
}

// MARK: - what a failure is not

@MainActor
@Test func aFailedReadIsNeverReportedAsLocked() async {
    // "You do not own enough" is a claim about the user. A dropped connection
    // is not — the same distinction `ShadeClaim.unavailable` draws.
    let model = await loaded(RankSessionModel(
        userItemID: UUID(),
        store: store(shelf: [], categories: [], failingShelf: true)
    ))

    #expect(model.state == .unavailable("the connection dropped"))
}

@MainActor
@Test func anItemThatIsNoLongerOnTheShelfIsNotLockedEither() async throws {
    let model = try await loaded(RankSessionModel(
        userItemID: UUID(),
        store: store(shelf: [row()], categories: [category()])
    ))

    guard case let .unavailable(message) = model.state else {
        Issue.record("a missing row is not a lock")
        return
    }
    #expect(message.contains("shelf"))
}

// MARK: - naming a contender

@MainActor
@Test func aContenderIsNamedWithoutAStraySeparator() async throws {
    // GLO-63: never a " · " standing in for a variant the catalog did not
    // return.
    let candidate = UUID()
    let bare = UUID()
    let model = try await loaded(RankSessionModel(
        userItemID: candidate,
        store: store(
            shelf: [
                row(id: candidate),
                row(id: bare, name: "cloud paint", variantLabel: nil),
                row()
            ],
            categories: [category()]
        )
    ))

    #expect(model.name(of: candidate) == "pocket blush · freckle")
    #expect(model.name(of: bare) == "cloud paint")
    #expect(model.name(of: UUID()) == "")
}
