import DataKit
import Foundation
import Testing
@testable import Profile

private func decoded(
    handle: String = "juli_r",
    shelfVisible: Bool = true,
    rankingsVisible: Bool = false,
    routinesVisible: Bool = false,
    badgeAnchor: String? = nil
) -> PublicProfile {
    let anchor = badgeAnchor.map { "\"\($0)\"" } ?? "null"
    let json = Data("""
    {"handle":"\(handle)","display_name":null,"avatar_seed":null,"bio":null,
     "badge_skin_type":null,"badge_anchor":\(anchor),"badge_hair_pattern":null,
     "followers":3,"following":9,"shelf_n":5,"ranked_lists_n":2,
     "shelf_visible":\(shelfVisible),"rankings_visible":\(rankingsVisible),
     "routines_visible":\(routinesVisible)}
    """.utf8)
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PublicProfile.self, from: json)
}

private func store(
    profile: @escaping @Sendable (String) async throws -> PublicProfile? = { _ in decoded() },
    isFollowing: @escaping @Sendable (UUID) async throws -> Bool = { _ in false },
    canFollow: @escaping @Sendable (UUID) async throws -> Bool = { _ in true },
    follow: @escaping @Sendable (UUID) async throws -> Void = { _ in },
    unfollow: @escaping @Sendable (UUID) async throws -> Void = { _ in },
    suggestions: @escaping @Sendable (Int) async throws -> [SuggestedPerson] = { _ in [] }
) -> ViewedProfileStore {
    ViewedProfileStore(
        profile: profile, isFollowing: isFollowing, canFollow: canFollow,
        follow: follow, unfollow: unfollow, suggestions: suggestions
    )
}

@MainActor
@Test func aMissingProfileIsOneStateNotFour() async {
    // No such handle, a minor owner, a block in either direction, otherwise
    // unreachable — all arrive as nil and stay indistinguishable. §1.5: "not
    // found" and "blocked" are the same response, because a screen that said
    // "they blocked you" leaks what the block exists to prevent.
    let model = ViewedProfileModel(store: store(profile: { _ in nil }), handle: "ghost")
    await model.load()
    #expect(model.isUnavailable)
    #expect(model.profile == nil)
    // And no error — this is an answer, not a failure.
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func aBlockedViewerSeesTheSameThingAsAWrongHandle() async {
    // The two cases the RPC deliberately conflates, asserted to behave
    // identically here so a future refactor cannot pull them apart.
    let ghost = ViewedProfileModel(store: store(profile: { _ in nil }), handle: "nobody")
    let blocked = ViewedProfileModel(store: store(profile: { _ in nil }), handle: "juli_r")
    await ghost.load()
    await blocked.load()
    #expect(ghost.isUnavailable == blocked.isUnavailable)
    #expect(ghost.followState == blocked.followState)
}

@MainActor
@Test func followIsUnavailableWithoutAUserID() async {
    // public_profile returns no user id, on purpose — a handle→id mapping
    // would make the follow graph enumerable. Without an id from the caller
    // the profile still renders, minus the control.
    let model = ViewedProfileModel(store: store(), handle: "juli_r", userID: nil)
    await model.load()
    #expect(model.profile != nil)
    #expect(model.followState == .unavailable)
}

@MainActor
@Test func aFollowableStrangerGetsTheButton() async {
    let model = ViewedProfileModel(store: store(), handle: "juli_r", userID: UUID())
    await model.load()
    #expect(model.followState == .notFollowing)
}

@MainActor
@Test func someoneAlreadyFollowedShowsFollowing() async {
    let model = ViewedProfileModel(
        store: store(isFollowing: { _ in true }), handle: "juli_r", userID: UUID()
    )
    await model.load()
    #expect(model.followState == .following)
}

@MainActor
@Test func aMinorOrBlockedTargetGetsNoControlAtAll() async {
    // Absent, not disabled. A greyed button invites "why not", and the honest
    // answer is one we must not give.
    let model = ViewedProfileModel(
        store: store(canFollow: { _ in false }), handle: "juli_r", userID: UUID()
    )
    await model.load()
    #expect(model.followState == .unavailable)
}

@MainActor
@Test func followingIsOptimisticAndRevertsOnFailure() async {
    struct Boom: Error {}
    let model = ViewedProfileModel(
        store: store(follow: { _ in throw Boom() }), handle: "juli_r", userID: UUID()
    )
    await model.load()
    #expect(model.followState == .notFollowing)
    await model.toggleFollow()
    #expect(model.followState == .notFollowing)
    #expect(model.errorMessage != nil)
}

@MainActor
@Test func followThenUnfollowRoundTrips() async {
    let model = ViewedProfileModel(store: store(), handle: "juli_r", userID: UUID())
    await model.load()
    await model.toggleFollow()
    #expect(model.followState == .following)
    await model.toggleFollow()
    #expect(model.followState == .notFollowing)
}

@MainActor
@Test func lockedSurfacesAreNamedPrivateRatherThanHidden() async {
    // Hiding leaves the viewer unsure the surface exists. "private" is true,
    // says nothing about the viewer, and reads the same whether the owner's
    // scope is `only you` or `friends`.
    let model = ViewedProfileModel(store: store(), handle: "juli_r")
    await model.load()
    #expect(model.surfaces.count == 3)
    #expect(model.surfaces.first { $0.label == "shelf" }?.visible == true)
    #expect(model.surfaces.first { $0.label == "rankings" }?.visible == false)
}

@MainActor
@Test func anEmptySuggestionListIsCorrectNotBroken() async {
    // Reasons are gated on profile_badges, which default false. Empty is the
    // expected state until people opt in, and the card says so rather than
    // spinning forever.
    let model = SuggestedPeopleModel(store: store(suggestions: { _ in [] }))
    await model.load()
    #expect(model.isEmptyForGoodReason)
    #expect(model.emptyLine.contains("chosen to share"))
}

@MainActor
@Test func suggestionsSurviveAFailedRead() async {
    // A failure and an empty result look the same to the card on purpose:
    // there is nothing useful a viewer can do about either, and an error
    // banner on a peripheral card is noise.
    struct Boom: Error {}
    let model = SuggestedPeopleModel(store: store(suggestions: { _ in throw Boom() }))
    await model.load()
    #expect(model.isEmptyForGoodReason)
}
