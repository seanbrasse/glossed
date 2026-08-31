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
        visibility: .onlyYou, startedOn: startedOn, createdAt: Date(timeIntervalSince1970: 0), steps: steps
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
    caption: String? = "glass skin sunday", photoN: Int = 3, isPublished: Bool = true
) -> ProfileLook {
    ProfileLook(id: UUID(), caption: caption, photoN: photoN, isPublished: isPublished)
}

private func scopesStore(
    shelf: PrivacyScope = .onlyYou, rankings: PrivacyScope = .onlyYou,
    routines: PrivacyScope = .onlyYou, looks: PrivacyScope = .onlyYou
) -> ProfileScopesStore {
    ProfileScopesStore(scopes: {
        PrivacyScopes(shelf: shelf, rankings: rankings, routines: routines, looks: looks)
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

// MARK: - The scope mark, which is what earns the preview's deletion

@MainActor
@Test func eachTabCarriesItsOwnSurfacesScope() async {
    // GLOSSED has four per-surface scopes where Instagram has one account
    // switch. The mark is the whole reason `what a stranger sees` can go.
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: { [] }),
        routines: ProfileRoutinesStore(mine: { [] }),
        shelf: ProfileShelfStore(mine: { [] }),
        scopes: scopesStore(shelf: .publicScope, routines: .friends, looks: .onlyYou)
    )
    await model.load()
    #expect(model.mark(for: .looks) == .onlyYou)
    #expect(model.mark(for: .routines) == .friends)
    #expect(model.mark(for: .shelf) == .publicToAnyone)
}

@Test func looksHasItsOwnScopeColumnAndDoesNotBorrowOne() {
    // Probed, not assumed: `visibility_surface` has four members and `looks`
    // is one of them, so the looks tab's mark is a read rather than an
    // invention. (It ships inert until Phase 2, which is a fact about what
    // consults it, not about whether the column exists.)
    #expect(VisibilitySurface.allCases.contains(.looks))
    #expect(ProfileTab.looks.surface == .looks)
}

@Test func collectionsHaveNoAccountLevelSurfaceSoTheirMarkIsTheCeiling() {
    // `visibility_surface` is shelf · rankings · routines · looks.
    // `collections.visibility` is a per-row column, so there is no account
    // scope to read and the tab states the most any stranger could reach.
    #expect(ProfileTab.collections.surface == nil)
    #expect(ProfileScopeMark.ceiling(of: []) == .onlyYou)
    #expect(ProfileScopeMark.ceiling(of: [.onlyYou, .onlyYou]) == .onlyYou)
    #expect(ProfileScopeMark.ceiling(of: [.onlyYou, .friends]) == .friends)
    // One public among five private still marks public: a privacy signal that
    // understates is the one that hurts.
    #expect(ProfileScopeMark.ceiling(of: [.onlyYou, .friends, .publicScope]) == .publicToAnyone)
}

@MainActor
@Test func theCollectionsMarkFollowsTheCollectionsActuallyLoaded() async {
    let model = ProfileTabsModel(
        collections: ProfileCollectionsStore(mine: {
            [collection(visibility: .onlyYou), collection(visibility: .publicScope)]
        }),
        scopes: scopesStore()
    )
    await model.load()
    #expect(model.mark(for: .collections) == .publicToAnyone)
}

@MainActor
@Test func withNoScopesSeamNoTabCarriesAMark() async {
    // The strip draws nothing rather than guessing. A privacy signal that
    // guesses is worse than one that waits.
    let model = ProfileTabsModel(looks: ProfileLooksStore(mine: { [] }))
    await model.load()
    #expect(model.mark(for: .looks) == nil)
}

@MainActor
@Test func aFailedScopesReadLeavesTheMarksAbsentRatherThanSayingOnlyYou() async {
    // The all-private default is right for a user with no row — the repository
    // applies it — and wrong for a read that failed, where "only you" would be
    // an assurance nobody checked.
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: { [] }),
        scopes: ProfileScopesStore(scopes: {
            throw GlossedError(.offline, userMessage: "you're offline.")
        })
    )
    await model.load()
    #expect(model.mark(for: .looks) == nil)
    #expect(model.errorMessage == "you're offline.")
}

@Test func theMarkWearsPrivacyScopesOwnWords() {
    // "only you", never "just you" (Sean, Aug 29).
    #expect(ProfileScopeMark.onlyYou.label == "only you")
    #expect(ProfileScopeMark.friends.label == "friends")
    #expect(ProfileScopeMark.publicToAnyone.label == "public")
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
