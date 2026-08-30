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
@Test func bothSeamsWiredGivesTheFramesTwoSegmentsInItsOrder() async {
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
