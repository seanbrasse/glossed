import DataKit
import Foundation
import Testing
@testable import Profile

private func profile(shelfN: Int = 0, followers: Int = 0, following: Int = 0, ranked: Int = 0) -> PublicProfile {
    let json = Data("""
    {"handle":"maya_k","display_name":null,"avatar_seed":null,"bio":null,
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
    #expect(!model.handleAwaitingReview)
}

@MainActor
@Test func aHandleWithNoPublicProfileYetSaysAwaitingReview() async {
    // claim_handle writes a PENDING public_texts row and a public surface
    // renders only approved (§3.2). With moderation parked nothing approves
    // it, so the profile must keep saying so rather than showing a handle
    // strangers cannot see.
    let model = OwnProfileModel(store: store(profileFor: { _ in nil }))
    await model.load()
    #expect(model.handleAwaitingReview)
}

@MainActor
@Test func everyBadgeStartsOff() async {
    // All three default false. They are the only path by which skin type, the
    // anchor shade and hair pattern reach another human (§3.4).
    let model = OwnProfileModel(store: store())
    await model.load()
    for row in BadgeRow.all {
        #expect(!model.badges.isOn(row.badge))
    }
}

@MainActor
@Test func turningOneBadgeOnLeavesTheOthersOff() async {
    // A write that reset its neighbours would publish Regulated data the user
    // never chose to publish.
    let model = OwnProfileModel(store: store())
    await model.load()
    await model.setBadge(.anchor, on: true)
    #expect(model.badges.showAnchor)
    #expect(!model.badges.showSkinType)
    #expect(!model.badges.showHairPattern)
}

@MainActor
@Test func aFailedBadgeWriteReverts() async {
    // A switch that stays on after a failed write tells the user they are
    // publishing something they are not — or that they are not publishing
    // something they are. Both are worse than an error.
    struct Boom: Error {}
    let model = OwnProfileModel(store: store(setBadge: { _, _ in throw Boom() }))
    await model.load()
    await model.setBadge(.skinType, on: true)
    #expect(!model.badges.showSkinType)
    #expect(model.errorMessage != nil)
}

@Test func everyBadgeRowSaysWhatItPublishes() {
    // The consequence belongs next to the control, not in a policy nobody
    // opens. Each row names what becomes visible and to whom.
    #expect(BadgeRow.all.count == ProfileBadges.Badge.allCases.count)
    for row in BadgeRow.all {
        #expect(row.title == row.title.lowercased())
        #expect(row.detail == row.detail.lowercased())
        #expect(row.detail.contains("profile") || row.detail.contains("suggested"))
    }
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

@Test func badgeApplicationIsIndependentPerFlag() {
    // Exhaustive: every badge, both directions, leaves the other two alone.
    for badge in ProfileBadges.Badge.allCases {
        let on = OwnProfileModel.applying(badge, on: true, to: ProfileBadges())
        #expect(on.isOn(badge))
        for other in ProfileBadges.Badge.allCases where other != badge {
            #expect(!on.isOn(other))
        }
    }
}
