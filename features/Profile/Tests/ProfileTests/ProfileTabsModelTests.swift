import DataKit
import Foundation
import Testing
@testable import Profile

private func step(_ position: Int, _ brand: String, _ product: String, _ shade: String? = nil) -> RoutineStep {
    RoutineStep(
        position: position, userItemID: UUID(), brandName: brand,
        productName: product, variantLabel: shade
    )
}

private func routine(
    title: String = "morning glass skin",
    slot: RoutineSlot = .am,
    startedOn: Date? = nil,
    steps: [RoutineStep] = []
) -> MyRoutine {
    MyRoutine(
        routineID: UUID(), title: title, slot: slot,
        startedOn: startedOn, createdAt: Date(timeIntervalSince1970: 0), steps: steps
    )
}

/// 1 March 2026, 00:00 UTC — a Postgres `date` as the decoder hands it over.
private let marchFirst = Date(timeIntervalSince1970: 1_772_323_200)

private func collection(
    title: String = "wash day kit", tint: String? = "mint", itemN: Int = 6
) -> ProfileCollection {
    ProfileCollection(id: UUID(), title: title, tint: tint, itemN: itemN)
}

@MainActor
@Test func aTabWithNoSeamBehindItNeverAppears() {
    // The frame declares both segments because its data is a fixture. A
    // segment in front of a surface that cannot answer is the drawer's
    // "collections land with GLO-21" mistake in different words.
    let model = ProfileTabsModel(routines: ProfileRoutinesStore(mine: { [] }))
    #expect(model.tabs == [.routines])
}

@MainActor
@Test func bothSeamsWiredGivesTheFramesTwoSegmentsInItsOrder() {
    let model = ProfileTabsModel(
        routines: ProfileRoutinesStore(mine: { [] }),
        collections: ProfileCollectionsStore(mine: { [] })
    )
    #expect(model.tabs == [.routines, .collections])
    // The frame opens on routines.
    #expect(model.tab == .routines)
}

@MainActor
@Test func withOnlyCollectionsWiredTheScreenOpensOnTheTabThatExists() async {
    // Rather than on `routines`, which would be a blank pane behind a control
    // that does not offer the alternative.
    let model = ProfileTabsModel(
        routines: nil, collections: ProfileCollectionsStore(mine: { [collection()] })
    )
    await model.load()
    #expect(model.tab == .collections)
    #expect(model.collections.count == 1)
}

@MainActor
@Test func oneTabFailingDoesNotBlankTheOther() async {
    // A user with routines and a collections read that timed out should still
    // see their routines.
    let model = ProfileTabsModel(
        routines: ProfileRoutinesStore(mine: { [routine()] }),
        collections: ProfileCollectionsStore(mine: {
            throw GlossedError(.offline, userMessage: "you're offline.")
        })
    )
    await model.load()
    #expect(model.routines.count == 1)
    #expect(model.collections.isEmpty)
    #expect(model.errorMessage == "you're offline.")
}

// MARK: - Edit mode and rename (GLO-230)

@MainActor
private func editableModel(
    routines: [MyRoutine] = [],
    rename: @escaping @Sendable (UUID, String) async throws -> Void = { _, _ in }
) -> ProfileTabsModel {
    ProfileTabsModel(routines: ProfileRoutinesStore(mine: { routines }, rename: rename))
}

@MainActor
@Test func editProfileIsNotOfferedWhenNothingCanBeRenamed() async {
    // A control that turns nothing into a target is a control that does
    // nothing, and this project has shipped that once already (GLO-189).
    let readOnly = ProfileTabsModel(routines: ProfileRoutinesStore(mine: { [] }))
    #expect(!readOnly.canEdit)
    #expect(editableModel().canEdit)
}

@MainActor
@Test func theButtonAndItsHintAreTheFramesWords() async {
    let model = editableModel()
    #expect(model.editButtonLabel == "edit profile")
    #expect(model.editHint == nil)
    model.toggleEditing()
    #expect(model.editButtonLabel == "done editing")
    #expect(model.editHint == "tap any card to rename it")
}

@MainActor
@Test func leavingEditModeClosesAnOpenRenameSheet() async {
    let model = editableModel()
    model.toggleEditing()
    model.beginRename(RenameTarget(kind: .routine, id: UUID(), value: "am"))
    #expect(model.renaming != nil)
    model.toggleEditing()
    #expect(model.renaming == nil)
}

@MainActor
@Test func aCardIsNotARenameTargetUntilEditModeIsOn() async {
    let model = editableModel()
    model.beginRename(RenameTarget(kind: .routine, id: UUID(), value: "am"))
    #expect(model.renaming == nil)
}

@MainActor
@Test func aSavedRenameUpdatesTheRowInPlaceAndTrimsFirst() async {
    let existing = routine(title: "am")
    nonisolated(unsafe) var wrote: (UUID, String)?
    let model = editableModel(routines: [existing], rename: { wrote = ($0, $1) })
    await model.load()
    model.toggleEditing()
    model.beginRename(RenameTarget(kind: .routine, id: existing.routineID, value: "  morning glass skin  "))
    await model.saveRename()

    #expect(wrote?.0 == existing.routineID)
    // Trimmed on this side too, so the list and the column cannot disagree
    // about what landed.
    #expect(wrote?.1 == "morning glass skin")
    #expect(model.routines.first?.title == "morning glass skin")
    // The steps and the slot survive the rewrite.
    #expect(model.routines.first?.slot == .am)
    #expect(model.renaming == nil)
}

@MainActor
@Test func aBlankNameIsRefusedBeforeTheRoundTrip() async {
    nonisolated(unsafe) var called = false
    let model = editableModel(routines: [routine()], rename: { _, _ in called = true })
    await model.load()
    model.toggleEditing()
    model.beginRename(RenameTarget(kind: .routine, id: UUID(), value: "   "))
    await model.saveRename()
    #expect(!called)
    #expect(model.errorMessage == "give it a name.")
    // The sheet stays open — the words are still there to fix.
    #expect(model.renaming != nil)
}

@MainActor
@Test func aFailedRenameKeepsTheSheetAndTheTypedWords() async {
    let existing = routine(title: "am")
    let model = editableModel(routines: [existing], rename: { _, _ in
        throw GlossedError(.offline, userMessage: "you're offline.")
    })
    await model.load()
    model.toggleEditing()
    model.beginRename(RenameTarget(kind: .routine, id: existing.routineID, value: "pm reset"))
    await model.saveRename()
    #expect(model.errorMessage == "you're offline.")
    #expect(model.renaming?.value == "pm reset")
    // And the list still says what the database says.
    #expect(model.routines.first?.title == "am")
}

@Test func theEyebrowNamesWhatIsBeingRenamed() {
    // The kit builds it by uppercasing the tab key and dropping the trailing s.
    #expect(RenameTarget(kind: .routine, id: UUID(), value: "").eyebrow == "RENAME ROUTINE")
    #expect(RenameTarget(kind: .collection, id: UUID(), value: "").eyebrow == "RENAME COLLECTION")
}

@MainActor
@Test func theWriteFollowsTheTargetNotTheTabShowing() async {
    // A tab switched under an open sheet must not send a routine's id to the
    // collections rename.
    nonisolated(unsafe) var routineWrites = 0
    nonisolated(unsafe) var collectionWrites = 0
    let model = ProfileTabsModel(
        routines: ProfileRoutinesStore(mine: { [] }, rename: { _, _ in routineWrites += 1 }),
        collections: ProfileCollectionsStore(mine: { [] }, rename: { _, _ in collectionWrites += 1 })
    )
    model.toggleEditing()
    model.beginRename(RenameTarget(kind: .routine, id: UUID(), value: "am"))
    model.tab = .collections
    await model.saveRename()
    #expect(routineWrites == 1)
    #expect(collectionWrites == 0)
}

@Test func theProductsLineIsSingularForOne() {
    #expect(ProfileTabsModel.productsLine(0) == "0 products")
    #expect(ProfileTabsModel.productsLine(1) == "1 product")
    #expect(ProfileTabsModel.productsLine(12) == "12 products")
}

@MainActor
@Test func anUnknownCoverTintDrawsUntintedRatherThanFailing() {
    // `collections.cover_tint` is nullable text with no check constraint, so
    // the column will accept anything. A cosmetic value must never be able to
    // take the grid down.
    #expect(CollectionCard.tint("butter") == .butter)
    #expect(CollectionCard.tint("cherry") == .cherry)
    #expect(CollectionCard.tint("mint") == .mint)
    #expect(CollectionCard.tint("lilac") == .lilac)
    #expect(CollectionCard.tint(nil) == .plain)
    #expect(CollectionCard.tint("chartreuse") == .plain)
}

@MainActor
@Test func withNoStoresAtAllTheWholeLowerHalfIsAbsent() async {
    let model = ProfileTabsModel(routines: nil)
    #expect(model.tabs.isEmpty)
    await model.load()
    // Nothing to read is not a failure — the app layer has not wired the seam.
    #expect(model.errorMessage == nil)
    #expect(model.routines.isEmpty)
}

@MainActor
@Test func routinesLoadInTheOrderTheRepositoryGivesThem() async {
    let model = ProfileTabsModel(routines: ProfileRoutinesStore(mine: {
        [routine(title: "morning glass skin"), routine(title: "pm reset", slot: .pm)]
    }))
    await model.load()
    #expect(model.routines.map(\.title) == ["morning glass skin", "pm reset"])
    #expect(!model.isLoading)
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func aFailedReadSaysSoInTheRepositorysOwnWords() async {
    let model = ProfileTabsModel(routines: ProfileRoutinesStore(mine: {
        throw GlossedError(.offline, userMessage: "you're offline.")
    }))
    await model.load()
    #expect(model.errorMessage == "you're offline.")
}

@Test func theStepsLineCountsStepsAndNamesTheSlot() {
    #expect(
        ProfileTabsModel.stepsLine(routine(slot: .am, steps: [step(0, "cosrx", "snail mucin")]))
            == "1 step · am"
    )
    #expect(
        ProfileTabsModel.stepsLine(routine(slot: .pm, steps: []))
            == "0 steps · pm"
    )
}

@Test func theStepsLineAddsSinceOnlyWhenAStartDateExists() {
    // `started_on` is a Postgres `date`. Formatted in the device's zone it
    // walks back a month for anyone west of Greenwich, so the formatter is
    // pinned to UTC.
    #expect(ProfileTabsModel.sinceWord(nil) == nil)
    #expect(ProfileTabsModel.sinceWord(marchFirst) == "mar 2026")
    #expect(
        ProfileTabsModel.stepsLine(routine(slot: .washDay, startedOn: marchFirst))
            == "0 steps · wash day · since mar 2026"
    )
}

@Test func theSlotWearsTheKitsWordsNotDataKitsLabel() {
    // GLO-210: `RoutineSlot.label` says morning/evening, the kit says am/pm.
    // Delete this mapping — and this test — when the DataKit fix lands.
    #expect(RoutineSlot.am.label == "morning")
    #expect(ProfileTabsModel.slotWord(.am) == "am")
    #expect(ProfileTabsModel.slotWord(.pm) == "pm")
    #expect(ProfileTabsModel.slotWord(.weekly) == "weekly")
    #expect(ProfileTabsModel.slotWord(.washDay) == "wash day")
}

@Test func aStepNamesTheThingYouOwnAndSkipsTheShadeWhenThereIsNone() {
    #expect(ProfileTabsModel.stepLine(step(0, "cosrx", "snail mucin")) == "cosrx · snail mucin")
    #expect(
        ProfileTabsModel.stepLine(step(1, "fenty", "pro filt'r", "240"))
            == "fenty · pro filt'r · 240"
    )
}
