import DataKit
import Foundation
import Testing
@testable import Collections

// The edit screen's rules (GLO-272) for collections: the save button arms on
// the first change, a save writes only the diffs, and a failure keeps every
// staged edit. The writes are recorded closures — no repository present.

private let lipstick = CollectionItem(id: UUID(), name: "pro filt'r", brand: "fenty beauty")
private let serum = CollectionItem(id: UUID(), name: "niacinamide 10%", brand: "the ordinary")
private let mist = CollectionItem(id: UUID(), name: "you", brand: "glossier")

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
    shelf: [CollectionItem] = [lipstick, serum, mist]
) -> CollectionsStore {
    CollectionsStore(
        mine: { [] },
        shelf: { shelf },
        items: { _ in [] },
        create: { _, _, _ in },
        rename: { _, _ in try recorder.record("rename") },
        addItem: { _, _, position in try recorder.record("add@\(position)") },
        removeItem: { _, _ in try recorder.record("remove") },
        setVisibility: { _, _ in try recorder.record("visibility") },
        remove: { _ in try recorder.record("delete") }
    )
}

@MainActor
private func makeModel(
    title: String = "holy grails only",
    visibility: PrivacyScope = .onlyYou,
    items: [CollectionItem] = [lipstick, serum],
    store: CollectionsStore
) -> CollectionEditModel {
    CollectionEditModel(
        collectionID: UUID(),
        baseline: CollectionEditModel.Baseline(title: title, visibility: visibility, items: items),
        store: store
    )
}

@MainActor
@Test func theSaveButtonArmsOnTheFirstChangeAndNotOnWhitespace() {
    let model = makeModel(store: recordingStore(Recorder()))
    #expect(!model.isDirty)
    model.title = "holy grails only   "
    #expect(!model.isDirty, "whitespace is not a change")
    model.title = ""
    #expect(!model.isDirty, "an empty title is invalid, not a change — the save stays disarmed")
    model.title = "grails, all of them"
    #expect(model.isDirty)
}

@MainActor
@Test func aSaveWritesOnlyTheDiffs() async {
    let recorder = Recorder()
    let model = makeModel(store: recordingStore(recorder))
    model.visibility = .friends
    #expect(await model.save())
    #expect(recorder.writes == ["visibility"], "the untouched title and items are never re-written")
    #expect(!model.isDirty)
}

@MainActor
@Test func itemEditsDiffAndAddsLandAfterTheSurvivors() async {
    let recorder = Recorder()
    let model = makeModel(store: recordingStore(recorder))
    model.items.removeAll { $0.id == serum.id }
    model.items.append(mist)
    _ = await model.save()
    // One remove, one add — positioned after the baseline set, and content
    // lands before any reach write would.
    #expect(recorder.writes == ["remove", "add@2"])
}

@MainActor
@Test func aFailedSaveKeepsEveryStagedEditAndNamesItself() async {
    let recorder = Recorder()
    recorder.failing = ["rename"]
    let model = makeModel(store: recordingStore(recorder))
    model.title = "won't land"
    model.visibility = .publicScope
    #expect(await model.save() == false)
    #expect(model.title == "won't land")
    #expect(model.isDirty)
    #expect(model.phase == .failed("nope"))
    // rename failed FIRST (content before reach) — visibility was never
    // attempted, so nothing widened under a half-saved edit.
    #expect(recorder.writes == ["rename"])
}

@MainActor
@Test func addablesOffersTheShelfMinusWhatIsAlreadyHeld() async {
    let model = makeModel(store: recordingStore(Recorder()))
    let offer = await model.addables()
    #expect(offer.map(\.id) == [mist.id], "held items are not offered twice")
}

@MainActor
@Test func deleteIsItsOwnConfirmedPath() async {
    let recorder = Recorder()
    let model = makeModel(store: recordingStore(recorder))
    #expect(await model.delete())
    #expect(recorder.writes == ["delete"])
}
