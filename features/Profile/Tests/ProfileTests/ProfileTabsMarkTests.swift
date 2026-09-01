import DataKit
import Foundation
import Testing
@testable import Profile

// The scope mark, lifted out of `ProfileTabsModelTests.swift` when GLO-274's
// per-item marks took that file past SwiftLint's 300-line ceiling. Fixtures
// stay next door and are internal rather than file-private so both files read
// the same rows.

// Fixtures are file-private here, matching `ProfileCardCopyTests` — top-level
// `private` is file-scoped, so a shared internal copy would be a redeclaration
// against the ones next door rather than a reuse of them.

private func routine(visibility: PrivacyScope = .onlyYou) -> MyRoutine {
    MyRoutine(
        routineID: UUID(), title: "morning glass skin", slot: .am,
        visibility: visibility, startedOn: nil,
        createdAt: Date(timeIntervalSince1970: 0), steps: []
    )
}

private func collection(visibility: PrivacyScope = .onlyYou) -> ProfileCollection {
    ProfileCollection(
        id: UUID(), title: "wash day kit", tint: "mint",
        itemN: 6, visibility: visibility
    )
}

private func look(
    isPublished: Bool = true, visibility: PrivacyScope = .onlyYou
) -> ProfileLook {
    ProfileLook(
        id: UUID(), caption: "glass skin sunday", photoN: 3,
        isPublished: isPublished, visibility: visibility
    )
}

private func scopesStore(
    shelf: PrivacyScope = .onlyYou, rankings: PrivacyScope = .onlyYou
) -> ProfileScopesStore {
    ProfileScopesStore(scopes: { PrivacyScopes(shelf: shelf, rankings: rankings) })
}

// MARK: - The scope mark, which is what earns the preview's deletion

@MainActor
@Test func eachTabCarriesItsOwnSurfacesScope() async {
    // The mark is the whole reason `what a stranger sees` can go. Since 0053
    // it comes from two different places depending on the tab, and this
    // asserts both: the shelf still reads the account scope, while looks and
    // routines are the ceiling of the rows actually on screen.
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: {
            [look(visibility: .onlyYou), look(visibility: .friends)]
        }),
        routines: ProfileRoutinesStore(mine: {
            [routine(visibility: .publicScope), routine(visibility: .onlyYou)]
        }),
        shelf: ProfileShelfStore(mine: { [] }),
        scopes: scopesStore(shelf: .publicScope)
    )
    await model.load()
    // Ceilings, not averages: one friends look makes the tab friends, and one
    // public routine makes that tab public. Understating is the failure mode
    // that hurts on a privacy signal.
    #expect(model.mark(for: .looks) == .friends)
    #expect(model.mark(for: .routines) == .publicToAnyone)
    #expect(model.mark(for: .shelf) == .publicToAnyone)
}

@MainActor
@Test func aLooksMarkIsItsOwnRowsNotTheCollectionsBesideIt() async {
    // The second half of GLO-274's fix. `mark(for:)` fell through to
    // *collections'* ceiling for every tab without an account surface, so the
    // looks tab was marked by rows it does not contain — a privacy signal
    // reporting on the wrong things.
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: { [look(visibility: .onlyYou)] }),
        collections: ProfileCollectionsStore(mine: {
            [collection(visibility: .publicScope)]
        }),
        scopes: scopesStore()
    )
    await model.load()
    #expect(model.mark(for: .looks) == .onlyYou)
    #expect(model.mark(for: .collections) == .publicToAnyone)
}

@MainActor
@Test func anUnpublishedLookDoesNotMakeTheTabPublic() async {
    // The mark answers "the most any other person could reach". A draft
    // reaches nobody — `looks_public_read` tests `state = 'public'`, not the
    // visibility column — so counting one made the tab read `public` over a
    // look nobody can see. Caught by driving the fixed build: the profile
    // showed `looks · public` above a single card marked `draft`.
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: {
            [look(isPublished: false, visibility: .publicScope)]
        }),
        scopes: scopesStore()
    )
    await model.load()
    #expect(model.mark(for: .looks) == .onlyYou)

    // And it does count once published, or the mark would understate — which
    // is the direction that actually hurts.
    let published = ProfileTabsModel(
        looks: ProfileLooksStore(mine: {
            [look(isPublished: true, visibility: .publicScope)]
        }),
        scopes: scopesStore()
    )
    await published.load()
    #expect(published.mark(for: .looks) == .publicToAnyone)
}

@Test func looksAndRoutinesLostTheirAccountScopeAndReadTheirOwnRows() {
    // **This assertion is inverted from what it was, on purpose.** It used to
    // read `ProfileTab.looks.surface == .looks`, which was true of the enum
    // and false of the database: migration 0053 dropped
    // `privacy_scopes.looks` and `.routines` when GLO-272 moved those
    // decisions onto the rows. The old assertion passed while every profile
    // visit raised `column privacy_scopes.routines does not exist` (GLO-274)
    // — it tested the Swift enum against itself and never against the schema.
    //
    // `visibility_surface` still carries all four, because `can_view` still
    // takes them; what changed is where the answer is STORED. `ScopedSurface`
    // is that narrower set, and neither looks nor routines is in it.
    #expect(VisibilitySurface.allCases.contains(.looks))
    #expect(Set(ScopedSurface.allCases.map(\.rawValue)) == ["shelf", "rankings"])
    #expect(ProfileTab.looks.surface == nil)
    #expect(ProfileTab.routines.surface == nil)
    #expect(ProfileTab.shelf.surface == .shelf)
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
