import DataKit
import Foundation
import Testing
@testable import Profile

private func store(
    report: @escaping @Sendable (ReportSubject, UUID?, UUID?, ReportReason, String?) async throws
        -> Void = { _, _, _, _, _ in },
    block: @escaping @Sendable (UUID) async throws -> Void = { _ in }
) -> SafetyActionsStore {
    SafetyActionsStore(report: report, block: block)
}

@MainActor
@Test func aReasonIsRequiredBeforeSending() {
    let model = ReportModel(store: store(), subject: .profile, subjectUserID: UUID())
    #expect(!model.canSend)
    model.choose(.harassment)
    #expect(model.canSend)
}

@MainActor
@Test func theOutcomeDoesNotPromiseAReview() async {
    // Moderation is parked: the runbook is non-operative and nobody works the
    // queue. Saying "we'll review this" would promise what the system cannot
    // do, which is worse than saying nothing.
    let model = ReportModel(store: store(), subject: .profile, subjectUserID: UUID())
    model.choose(.spam)
    await model.send()
    #expect(model.sent)
    // The property is "makes no promise", not "avoids the word" — the honest
    // copy says "we're NOT reviewing reports yet", which contains it.
    for promise in ["we'll review", "will be reviewed", "under review", "we'll look"] {
        #expect(!model.outcomeLine.contains(promise))
    }
    #expect(model.outcomeLine.contains("not reviewing"))
}

@MainActor
@Test func blockingIsNamedAsTheThingThatActsNow() async {
    // The honest hierarchy while moderation is parked: the report is stored,
    // the block takes effect.
    let model = ReportModel(store: store(), subject: .profile, subjectUserID: UUID())
    model.choose(.harassment)
    await model.send()
    #expect(model.outcomeLine.contains("blocking is the thing that takes effect"))
}

@MainActor
@Test func blockingIsOfferedNotAssumed() async {
    let blocked = LockedFlag()
    let model = ReportModel(
        store: store(block: { _ in await blocked.set() }),
        subject: .profile, subjectUserID: UUID()
    )
    model.choose(.harassment)
    await model.send()
    #expect(await !blocked.value)
    #expect(!model.didBlock)
}

@MainActor
@Test func optingIntoBlockingBlocks() async {
    let model = ReportModel(store: store(), subject: .profile, subjectUserID: UUID())
    model.choose(.harassment)
    model.alsoBlock = true
    await model.send()
    #expect(model.didBlock)
    #expect(model.outcomeLine.contains("can't see you"))
}

@MainActor
@Test func aFailedBlockDoesNotUndoTheReport() async {
    // Two writes. The report landing is the part that matters, and the
    // confirmation must not claim a block that did not happen.
    struct Boom: Error {}
    let model = ReportModel(
        store: store(block: { _ in throw Boom() }),
        subject: .profile, subjectUserID: UUID()
    )
    model.choose(.harassment)
    model.alsoBlock = true
    await model.send()
    #expect(!model.didBlock)
    #expect(model.errorMessage != nil)
}

@MainActor
@Test func blockingIsNotOfferedWithoutSomeoneToBlock() {
    // Reporting a collection carries no subject user.
    let model = ReportModel(store: store(), subject: .collection, subjectID: UUID())
    #expect(!model.canBlock)
}

@MainActor
@Test func anEmptyDetailIsSentAsNilNotBlank() async {
    let captured = CapturedDetail()
    let model = ReportModel(
        store: store(report: { _, _, _, _, detail in await captured.set(detail) }),
        subject: .profile, subjectUserID: UUID()
    )
    model.choose(.other)
    model.detail = "   "
    await model.send()
    #expect(await captured.value == nil)
}

private actor LockedFlag {
    private(set) var value = false
    func set() {
        value = true
    }
}

private actor CapturedDetail {
    private(set) var value: String?
    func set(_ detail: String?) {
        value = detail
    }
}
