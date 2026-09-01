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
    steps: [RoutineStep] = [],
    visibility: PrivacyScope = .onlyYou
) -> MyRoutine {
    MyRoutine(
        routineID: UUID(), title: title, slot: slot,
        visibility: visibility, startedOn: startedOn,
        createdAt: Date(timeIntervalSince1970: 0), steps: steps
    )
}

/// 1 March 2026, 00:00 UTC — a Postgres `date` as the decoder hands it over.
private let marchFirst = Date(timeIntervalSince1970: 1_772_323_200)

private func collection(
    title: String = "wash day kit", tint: String? = "mint", itemN: Int = 6,
    visibility: PrivacyScope = .onlyYou
) -> ProfileCollection {
    ProfileCollection(id: UUID(), title: title, tint: tint, itemN: itemN, visibility: visibility)
}

private func look(
    caption: String? = "glass skin sunday", photoN: Int = 3, isPublished: Bool = true,
    visibility: PrivacyScope = .onlyYou
) -> ProfileLook {
    ProfileLook(
        id: UUID(), caption: caption, photoN: photoN,
        isPublished: isPublished, visibility: visibility
    )
}

private func scopesStore(
    shelf: PrivacyScope = .onlyYou, rankings: PrivacyScope = .onlyYou
) -> ProfileScopesStore {
    ProfileScopesStore(scopes: {
        PrivacyScopes(shelf: shelf, rankings: rankings)
    })
}

// MARK: - The tab set

@MainActor
@Test func looksIsTheDefaultTabAndComesFirst() {
    // Sean, GLO-261: "users will see their bio, pfp, name, and then looks as
    // default, or collections, or routines, etc."
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: { [] }),
        collections: ProfileCollectionsStore(mine: { [] }),
        routines: ProfileRoutinesStore(mine: { [] }),
        shelf: ProfileShelfStore(mine: { [] })
    )
    #expect(model.tabs == [.looks, .collections, .routines, .shelf])
    #expect(model.tab == .looks)
}

@MainActor
@Test func aTabWithNoSeamBehindItNeverAppears() {
    // A tab in front of a surface that cannot answer is the drawer's
    // "collections land with GLO-21" mistake in different words (GLO-189).
    let model = ProfileTabsModel(routines: ProfileRoutinesStore(mine: { [] }))
    #expect(model.tabs == [.routines])
}

@MainActor
@Test func withLooksUnwiredTheScreenOpensOnTheFirstTabThatExists() async {
    // Rather than on `looks`, which would be a blank pane behind a strip that
    // does not offer it.
    let model = ProfileTabsModel(collections: ProfileCollectionsStore(mine: { [collection()] }))
    await model.load()
    #expect(model.tab == .collections)
}

@MainActor
@Test func withNoStoresAtAllTheWholeLowerHalfIsAbsent() async {
    let model = ProfileTabsModel()
    #expect(model.tabs.isEmpty)
    await model.load()
    // Nothing to read is not a failure — the app layer has not wired the seam.
    #expect(model.errorMessage == nil)
    #expect(model.looks.isEmpty)
}

// MARK: - Reading

@MainActor
@Test func everyWiredTabLoadsTogether() async {
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: { [look()] }),
        collections: ProfileCollectionsStore(mine: { [collection()] }),
        routines: ProfileRoutinesStore(mine: { [routine()] }),
        shelf: ProfileShelfStore(mine: {
            [ProfileShelfEntry(id: UUID(), brandName: "cosrx", productName: "snail mucin")]
        })
    )
    await model.load()
    #expect(model.looks.count == 1)
    #expect(model.collections.count == 1)
    #expect(model.routines.count == 1)
    #expect(model.shelf.count == 1)
    #expect(!model.isLoading)
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func oneFailedReadDoesNotBlankTheOtherTabs() async {
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: {
            throw GlossedError(.offline, userMessage: "you're offline.")
        }),
        routines: ProfileRoutinesStore(mine: { [routine()] })
    )
    await model.load()
    #expect(model.errorMessage == "you're offline.")
    #expect(model.routines.count == 1)
}

@MainActor
@Test func drafsAreKeptOnYourOwnProfileAndSaySo() async {
    // `LooksRepository.mine()` returns every state. A draft you cannot see is
    // a draft you cannot finish.
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: { [look(isPublished: false), look()] })
    )
    await model.load()
    #expect(model.looks.count == 2)
    #expect(ProfileCardCopy.lookLine(photoN: 3, isPublished: false) == "3 photos · draft")
    #expect(ProfileCardCopy.lookLine(photoN: 1, isPublished: true) == "1 photo")
}

// MARK: - The empty state and its +

@MainActor
@Test func theEmptyStateIsTheWholeProfileNotOneTab() async {
    // Sean's `+` belongs to an empty profile. A `+` that appeared whenever the
    // open tab happened to be empty would sit under the shell's own one on a
    // profile that is not empty at all.
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: { [] }),
        routines: ProfileRoutinesStore(mine: { [routine()] })
    )
    await model.load()
    #expect(!model.isEmpty)
}

@MainActor
@Test func aProfileWithNothingOnAnyTabIsEmpty() async {
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: { [] }),
        collections: ProfileCollectionsStore(mine: { [] })
    )
    await model.load()
    #expect(model.isEmpty)
}

@Test func theComposerCopyNamesTheThingAndStops() {
    // GLO-189: no copy may imply a look is reviewed or promise an audience.
    #expect(ProfileComposable.allCases.map(\.label) == ["a look", "a collection", "a routine"])
}
