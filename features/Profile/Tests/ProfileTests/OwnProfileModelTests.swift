import DataKit
import Foundation
import Testing
@testable import Profile

private func profile(
    shelfN: Int = 0, followers: Int = 0, following: Int = 0, ranked: Int = 0,
    displayName: String? = nil
) -> PublicProfile {
    let name = displayName.map { "\"\($0)\"" } ?? "null"
    let json = Data("""
    {"handle":"maya_k","display_name":\(name),"avatar_seed":null,"bio":null,
     "badge_skin_type":null,"badge_anchor":null,"badge_hair_pattern":null,
     "followers":\(followers),"following":\(following),"shelf_n":\(shelfN),
     "ranked_lists_n":\(ranked),"shelf_visible":true,"rankings_visible":true,
     "routines_visible":true}
    """.utf8)
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PublicProfile.self, from: json)
}

private func store(
    handle: @escaping @Sendable () async throws -> String? = { "maya_k" },
    profileFor: @escaping @Sendable (String) async throws -> PublicProfile? = { _ in profile() },
    badges: @escaping @Sendable () async throws -> ProfileBadges = { ProfileBadges() },
    setBadge: @escaping @Sendable (ProfileBadges.Badge, Bool) async throws -> Void = { _, _ in }
) -> OwnProfileStore {
    OwnProfileStore(handle: handle, profile: profileFor, badges: badges, setBadge: setBadge)
}

@MainActor
@Test func noHandleIsAStateNotAnError() async {
    // The pre-claim state. A screen that treated it as a failure would show an
    // error to someone who has simply not got there yet.
    let model = OwnProfileModel(store: store(handle: { nil }))
    await model.load()
    #expect(model.needsHandle)
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func aClaimedHandleLoadsTheProfile() async {
    let model = OwnProfileModel(store: store(profileFor: { _ in profile(shelfN: 8, followers: 12) }))
    await model.load()
    #expect(!model.needsHandle)
    #expect(model.followersN == 12)
    #expect(!model.profileUnreachable)
}

@MainActor
@Test func aHandleWithNoReadableProfileSaysSoWithoutInventingAReview() async {
    // The handle is public immediately (GLO-187), so a missing profile read is
    // not a moderation state and must not be reported as one.
    let model = OwnProfileModel(store: store(profileFor: { _ in nil }))
    await model.load()
    #expect(model.profileUnreachable)
}

@MainActor
@Test func anEmptyShelfStillStatesItsN() async {
    // Zero is shown, not hidden. A claim that disappears when it is
    // unflattering is not evidence.
    let model = OwnProfileModel(store: store(profileFor: { _ in profile(shelfN: 0) }))
    await model.load()
    #expect(model.shelfLine.contains("0"))
}

@MainActor
@Test func theShelfLineIsSingularForOne() async {
    let model = OwnProfileModel(store: store(profileFor: { _ in profile(shelfN: 1) }))
    await model.load()
    #expect(model.shelfLine == "1 thing on your shelf")
}

@MainActor
@Test func yourOwnAvatarUsesTheSameNameEveryoneElseSees() async {
    // ViewedProfileView and StrangerPreviewView both draw the initial from
    // `displayName ?? handle`. This screen drew it from the handle alone,
    // which was invisible until #352 made a display name settable — and then
    // "rae" on @maya_k gave everyone else "r" and you "m". You would be the
    // only person seeing a different avatar than the one you have.
    let named = OwnProfileModel(store: store(profileFor: { _ in profile(displayName: "rae") }))
    await named.load()
    #expect(named.avatarName == "rae")

    // No display name set: the handle, exactly as the other two screens fall back.
    let unnamed = OwnProfileModel(store: store())
    await unnamed.load()
    #expect(unnamed.avatarName == "maya_k")

    // No handle either — the pre-claim state is not an error, and Avatar's own
    // rule turns "?" into the "?" glyph rather than an empty circle.
    let blank = OwnProfileModel(store: store(handle: { nil }, profileFor: { _ in nil }))
    await blank.load()
    #expect(blank.avatarName == "?")
}
