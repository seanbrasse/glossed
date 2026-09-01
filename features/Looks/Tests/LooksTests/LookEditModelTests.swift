import CoreGraphics
import DataKit
import Foundation
import Testing
@testable import Looks

// The edit screen's rules (GLO-272, Sean's uniform pattern): the save button
// arms on the FIRST change and not before, a save writes only the diffs, and
// a failure keeps every staged edit. All pure model — the writes are recorded
// closures, no database.

private let routineA = LinkablePick(id: UUID(), title: "morning glass skin")
private let routineB = LinkablePick(id: UUID(), title: "pm reset")
private let collectionA = LinkablePick(id: UUID(), title: "holy grails only")

@MainActor
private func makeModel(
    caption: String? = "golden hour",
    visibility: PrivacyScope = .publicScope,
    isPosted: Bool = true,
    board: LookTagBoard = LookTagBoard(),
    routines: [LinkablePick] = [routineA],
    collections: [LinkablePick] = [collectionA],
    store: LookEditStore = .recording(into: Recorder())
) -> LookEditModel {
    LookEditModel(
        baseline: LookEditModel.Baseline(
            caption: caption, visibility: visibility, isPosted: isPosted,
            board: board, routines: routines, collections: collections
        ),
        store: store
    )
}

/// Every write the store saw, in order — what "only the diffs" is asserted
/// against.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _writes: [String] = []
    var failing: Set<String> = []

    var writes: [String] {
        lock.withLock { _writes }
    }

    func record(_ name: String) throws {
        lock.withLock { _writes.append(name) }
        if failing.contains(name) {
            throw GlossedError(.unknown, userMessage: "nope")
        }
    }
}

private extension LookEditStore {
    static func recording(into recorder: Recorder) -> LookEditStore {
        LookEditStore(
            updateCaption: { _ in try recorder.record("caption") },
            setVisibility: { _ in try recorder.record("visibility") },
            setPosted: { _ in try recorder.record("posted") },
            replaceSpots: { _ in try recorder.record("spots") },
            setLinks: { _ in try recorder.record("links") },
            linkables: { LookLinkables(routines: [routineA, routineB], collections: [collectionA]) },
            delete: { try recorder.record("delete") }
        )
    }
}

@MainActor
@Test func theSaveButtonStartsDisarmedAndArmsOnTheFirstChange() {
    let model = makeModel()
    #expect(!model.isDirty) // disabled save button — Sean's spec
    model.caption = "golden hour, but longer"
    #expect(model.isDirty)
    model.caption = "golden hour"
    #expect(!model.isDirty) // undone by hand → nothing to save again
}

@MainActor
@Test func whitespaceAroundTheCaptionIsNotAChange() {
    let model = makeModel()
    model.caption = "golden hour  "
    #expect(!model.isDirty, "typed a space and deleted the thought — no save to offer")
}

@MainActor
@Test func aSaveWritesOnlyWhatChanged() async {
    let recorder = Recorder()
    let model = makeModel(store: .recording(into: recorder))
    model.visibility = .onlyYou // the archive gesture
    let saved = await model.save()
    #expect(saved)
    #expect(recorder.writes == ["visibility"], "an untouched caption is never re-written")
    #expect(!model.isDirty, "the baseline moved up — saving twice is a no-op")
}

@MainActor
@Test func contentWritesLandBeforeReachWrites() async {
    // The order is the safety property: if the caption write dies, the look
    // has not widened first — nobody sees half an edit at a new scope.
    let recorder = Recorder()
    let model = makeModel(visibility: .onlyYou, store: .recording(into: recorder))
    model.caption = "reworked"
    model.visibility = .publicScope
    model.isPosted = false
    _ = await model.save()
    #expect(recorder.writes == ["caption", "visibility", "posted"])
}

@MainActor
@Test func aFailedSaveKeepsEveryStagedEditAndNamesItself() async {
    let recorder = Recorder()
    recorder.failing = ["caption"]
    let model = makeModel(store: .recording(into: recorder))
    model.caption = "won't land"
    model.visibility = .friends
    let saved = await model.save()
    #expect(!saved)
    #expect(model.caption == "won't land", "failure loses nothing")
    #expect(model.isDirty, "still dirty — the retry re-arms from here")
    #expect(model.phase == .failed("nope"), "and it says so in the error's own words")
    // The caption failed BEFORE visibility was attempted (content first), so
    // the retry still owes both writes.
    #expect(recorder.writes == ["caption"])
}

@MainActor
@Test func linkEditsSaveAsDiffsNotAsTheWholeList() async {
    let recorder = Recorder()
    let model = makeModel(store: .recording(into: recorder))
    model.routines.append(routineB)
    model.collections.removeAll()
    let changes = model.linkChanges
    #expect(changes.addRoutineIDs == [routineB.id])
    #expect(changes.removeRoutineIDs.isEmpty)
    #expect(changes.removeCollectionIDs == [collectionA.id])
    _ = await model.save()
    #expect(recorder.writes == ["links"])
}

@MainActor
@Test func reorderingNothingLeavesTheLinksClean() {
    let model = makeModel()
    #expect(model.linkChanges.isEmpty)
    #expect(!model.isDirty)
}

@MainActor
@Test func deleteIsItsOwnPathAndDoesNotRequireDirtiness() async {
    let recorder = Recorder()
    let model = makeModel(store: .recording(into: recorder))
    #expect(!model.isDirty)
    let deleted = await model.delete()
    #expect(deleted)
    #expect(recorder.writes == ["delete"])
}

@MainActor
@Test func aFailedDeleteSaysSoAndTheLookSurvivesLocally() async {
    let recorder = Recorder()
    recorder.failing = ["delete"]
    let model = makeModel(store: .recording(into: recorder))
    let deleted = await model.delete()
    #expect(!deleted)
    #expect(model.phase == .failed("nope"))
}

@MainActor
@Test func unpostingStagesLikeEverythingElse() async {
    // "unpost it" is a staged edit behind the same save button — not an
    // immediate write like the old link chips.
    let recorder = Recorder()
    let model = makeModel(store: .recording(into: recorder))
    model.isPosted = false
    #expect(model.isDirty)
    #expect(recorder.writes.isEmpty, "nothing writes before save")
    _ = await model.save()
    #expect(recorder.writes == ["posted"])
}

@MainActor
@Test func theLadderReadsDraftOverAnyScopeAndWritesBothColumns() async {
    // One dial over two columns (Sean's night ruling): draft wins the read
    // whatever the scope says; a scope rung posts AT that scope; climbing
    // back to draft keeps the scope so the round trip restores everything.
    let recorder = Recorder()
    let model = makeModel(visibility: .friends, isPosted: false, store: .recording(into: recorder))
    #expect(model.reach == .draft, "a draft reads as draft even holding a friends scope")
    model.reach = .friends
    #expect(model.isPosted && model.visibility == .friends)
    _ = await model.save()
    #expect(recorder.writes == ["posted"], "same scope → only the state write")
    model.reach = .draft
    #expect(!model.isPosted)
    #expect(model.visibility == .friends, "the scope survives the descent")
    model.reach = .onlyYou
    #expect(
        model.isPosted && model.visibility == .onlyYou,
        "only-you is POSTED-private — the rung that is not draft"
    )
}
