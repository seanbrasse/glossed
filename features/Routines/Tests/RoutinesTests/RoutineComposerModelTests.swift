import DataKit
import Foundation
import Testing
@testable import Routines

// The composer's rules, fixtures on both sides of each (the session-12
// discipline): pickable and picked, first and last, named and namesless.

private func step(_ name: String) -> RoutineComposerModel.Step {
    RoutineComposerModel.Step(id: UUID(), name: name, brand: "b")
}

@MainActor
@Test func togglingAppendsToTheEndAndRemovesFromAnywhere() {
    let model = RoutineComposerModel()
    let cleanser = step("cleanser")
    let serum = step("serum")
    let spf = step("spf")
    model.toggle(cleanser)
    model.toggle(serum)
    model.toggle(spf)
    #expect(model.steps.map(\.name) == ["cleanser", "serum", "spf"]) // tap order IS the order
    model.toggle(serum) // out from the middle
    #expect(model.steps.map(\.name) == ["cleanser", "spf"])
    #expect(!model.isPicked(serum))
}

@MainActor
@Test func reorderSwapsNeighborsAndClampsAtBothEnds() {
    let model = RoutineComposerModel()
    let first = step("one")
    let second = step("two")
    model.toggle(first)
    model.toggle(second)
    model.move(first, up: true) // already first — no-op, not a crash
    #expect(model.steps.map(\.name) == ["one", "two"])
    model.move(second, up: false) // already last — no-op
    #expect(model.steps.map(\.name) == ["one", "two"])
    model.move(second, up: true)
    #expect(model.steps.map(\.name) == ["two", "one"])
}

@MainActor
@Test func saveNeedsANameAndAtLeastOneStep() {
    let model = RoutineComposerModel()
    #expect(!model.canSave) // nothing
    model.title = "   " // whitespace is not a name
    model.toggle(step("cleanser"))
    #expect(!model.canSave)
    model.title = "morning glass skin"
    #expect(model.canSave)
    model.toggle(model.steps[0]) // last step out again
    #expect(!model.canSave) // a titled empty sequence is a note, not a routine
}

@MainActor
@Test func saveHandsTheSchemaVocabularyToTheSeam() async {
    struct Row {
        let title: String
        let slot: String
        let ids: [UUID]
    }
    actor Written {
        var row: Row?
        func set(_ title: String, _ slot: String, _ ids: [UUID]) {
            row = Row(title: title, slot: slot, ids: ids)
        }
    }
    let written = Written()
    let model = RoutineComposerModel(store: RoutineStore(
        shelf: { [] },
        create: { await written.set($0, $1, $2) }
    ))
    let cleanser = step("cleanser")
    let mask = step("mask")
    model.title = "  wash day reset "
    model.slot = .washDay
    model.toggle(cleanser)
    model.toggle(mask)
    var landed = false
    model.save { landed = true }
    await model.task?.value
    let row = await written.row
    #expect(row?.title == "wash day reset") // trimmed
    #expect(row?.slot == "wash_day") // the enum's wire word, not the label
    #expect(row?.ids == [cleanser.id, mask.id]) // in order
    #expect(landed)
}

@MainActor
@Test func aFailedSaveKeepsTheRoutineAndSpeaksInWords() async {
    let model = RoutineComposerModel(store: RoutineStore(
        shelf: { [] },
        create: { _, _, _ in throw URLError(.timedOut) }
    ))
    model.title = "pm"
    model.toggle(step("serum"))
    var landed = false
    model.save { landed = true }
    await model.task?.value
    #expect(!landed)
    #expect(model.saveError?.code == .offline)
    #expect(model.steps.count == 1) // nothing lost
}

@MainActor
@Test func aFailedShelfLoadIsAnExplainedEmptyNotABlank() async {
    let model = RoutineComposerModel(store: RoutineStore(
        shelf: { throw URLError(.notConnectedToInternet) },
        create: { _, _, _ in }
    ))
    model.loadShelf()
    await model.task?.value
    #expect(model.shelf.isEmpty)
    #expect(!model.isLoadingShelf)
}

@Test func theSlotLabelsWearSpacesTheWireWordsWearUnderscores() {
    #expect(RoutineComposerModel.Slot.washDay.label == "wash day")
    #expect(RoutineComposerModel.Slot.washDay.rawValue == "wash_day")
    #expect(RoutineComposerModel.Slot.allCases.map(\.rawValue) == ["am", "pm", "weekly", "wash_day"])
}
