import DataKit
import Foundation
import Testing
@testable import Routines

// The routine edit screen's rules (GLO-272): the save arms on the first
// change — a NOTE edit included, which was Sean's per-step ask — save writes
// only the diffs, and a failure keeps every staged edit.

private let cleanser = RoutineComposerModel.Step(id: UUID(), name: "milky jelly", brand: "glossier")
private let serum = RoutineComposerModel.Step(
    id: UUID(), name: "niacinamide 10%", brand: "the ordinary", note: "three drops, pressed in"
)
private let spf = RoutineComposerModel.Step(id: UUID(), name: "unseen sunscreen", brand: "supergoop")
private let grails = LinkablePick(id: UUID(), title: "holy grails only")
private let spring = LinkablePick(id: UUID(), title: "spring shelf")

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

private func recordingStore(
    _ recorder: Recorder,
    shelf: [RoutineComposerModel.Step] = [cleanser, serum, spf],
    collections: [LinkablePick] = [grails, spring]
) -> RoutineEditStore {
    RoutineEditStore(
        rename: { _ in try recorder.record("rename") },
        setVisibility: { _ in try recorder.record("visibility") },
        replaceSteps: { steps in try recorder.record("steps(\(steps.count))") },
        linkCollections: { ids in try recorder.record("link(\(ids.count))") },
        unlinkCollection: { _ in try recorder.record("unlink") },
        remove: { try recorder.record("delete") },
        shelf: { shelf },
        collections: { collections }
    )
}

@MainActor
private func makeModel(
    steps: [RoutineComposerModel.Step] = [cleanser, serum],
    collections: [LinkablePick] = [grails],
    store: RoutineEditStore
) -> RoutineEditModel {
    RoutineEditModel(
        baseline: RoutineEditModel.Baseline(
            title: "morning glass skin", visibility: .onlyYou,
            steps: steps, collections: collections
        ),
        store: store
    )
}

@MainActor
@Test func aNoteEditAloneArmsTheSave() {
    // Sean's per-step ask, as the arming rule: changing WHAT YOU DO in a
    // step is an edit even when the step set has not moved.
    let model = makeModel(store: recordingStore(Recorder()))
    #expect(!model.isDirty)
    model.steps[1].note = "five drops now — winter"
    #expect(model.isDirty)
}

@MainActor
@Test func whitespaceNoteChurnIsNotAChange() {
    let model = makeModel(store: recordingStore(Recorder()))
    model.steps[0].note = "   "
    #expect(!model.isDirty, "the write path trims, so a save here would save nothing")
}

@MainActor
@Test func aNoteEditSavesTheStepSetAndNothingElse() async {
    let recorder = Recorder()
    let model = makeModel(store: recordingStore(recorder))
    model.steps[1].note = "two drops now"
    #expect(await model.save())
    #expect(recorder.writes == ["steps(2)"], "title, links and scope are never re-written")
    #expect(!model.isDirty)
}

@MainActor
@Test func reorderingStepsIsAChange() async {
    let recorder = Recorder()
    let model = makeModel(store: recordingStore(recorder))
    model.steps.swapAt(0, 1)
    #expect(model.isDirty, "order IS the routine")
    _ = await model.save()
    #expect(recorder.writes == ["steps(2)"])
}

@MainActor
@Test func linkEditsSaveAsDiffs() async {
    let recorder = Recorder()
    let model = makeModel(store: recordingStore(recorder))
    model.collections = [spring]
    _ = await model.save()
    #expect(recorder.writes == ["link(1)", "unlink"], "one add, one remove — never the whole list")
}

@MainActor
@Test func contentLandsBeforeReachAndAFailureKeepsEverything() async {
    let recorder = Recorder()
    recorder.failing = ["steps(1)"]
    let model = makeModel(store: recordingStore(recorder))
    model.steps.removeAll { $0.id == serum.id }
    model.visibility = .publicScope
    #expect(await model.save() == false)
    #expect(recorder.writes == ["steps(1)"], "visibility was never attempted — nothing widened")
    #expect(model.isDirty)
    #expect(model.phase == .failed("nope"))
}

@MainActor
@Test func theOffersExcludeWhatIsAlreadyHeld() async {
    let model = makeModel(store: recordingStore(Recorder()))
    let steps = await model.addableSteps()
    let picks = await model.addableCollections()
    #expect(steps.map(\.id) == [spf.id])
    #expect(picks.map(\.id) == [spring.id])
}

@MainActor
@Test func deleteIsItsOwnConfirmedPath() async {
    let recorder = Recorder()
    let model = makeModel(store: recordingStore(recorder))
    #expect(await model.delete())
    #expect(recorder.writes == ["delete"])
}
