import DataKit
import DesignSystem
import Foundation
import Testing
@testable import Profile

private func profile(
    shelfN: Int = 0, followers: Int = 0, following: Int = 0, ranked: Int = 0,
    displayName: String? = nil, bio: String? = nil
) -> PublicProfile {
    let name = displayName.map { "\"\($0)\"" } ?? "null"
    let bioJSON = bio.map { "\"\($0)\"" } ?? "null"
    let json = Data("""
    {"handle":"maya_k","display_name":\(name),"avatar_seed":null,"bio":\(bioJSON),
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
    // Zero is shown, not hidden. A count that disappears when it is
    // unflattering is not a count.
    let model = OwnProfileModel(store: store(profileFor: { _ in profile(shelfN: 0) }))
    await model.load()
    #expect(model.statLine == "0 followers · 0 following · 0 on your shelf")
}

@MainActor
@Test func theStatLineIsSeansThreeMetrics() async {
    // **Rewritten for GLO-261, not repaired.** This asserted the frame's
    // `34 shelved · 7 ranked lists · …`. Sean named the metrics himself:
    // "your followers, your following, maybe profile views, amount of things
    // on your shelf". Three of the four; profile views has no table, no
    // counter and no write path, and GLO-262 carries that cost.
    let model = OwnProfileModel(store: store(profileFor: { _ in
        profile(shelfN: 34, followers: 12, following: 9, ranked: 7)
    }))
    await model.load()
    #expect(model.statLine == "12 followers · 9 following · 34 on your shelf")
    // The ranked-list count is still read and still true — it is just not one
    // of the three Sean asked to see.
    #expect(model.rankedListsN == 7)
}

@MainActor
@Test func everyStatLineCountIsSingularForOne() async {
    let model = OwnProfileModel(store: store(profileFor: { _ in
        profile(shelfN: 1, followers: 1, following: 1, ranked: 1)
    }))
    await model.load()
    #expect(model.statLine == "1 follower · 1 following · 1 on your shelf")
}

@MainActor
@Test func theNameLeadsAndTheHandleSitsUnderIt() async {
    // Sean's sketch: `[avatar] display name / @handle`. This inverts #363,
    // which made the handle the h1 — the handle is still the profile's address
    // (GLO-187) and still on the identity line, one line down.
    let named = OwnProfileModel(store: store(profileFor: { _ in profile(displayName: "rae") }))
    await named.load()
    #expect(named.leadName == "rae")
    #expect(named.handleLine == "@maya_k")
}

@MainActor
@Test func withNoDisplayNameTheHandleTakesTheTopLineRatherThanLeavingItBlank() async {
    let unnamed = OwnProfileModel(store: store(profileFor: { _ in profile(displayName: nil) }))
    await unnamed.load()
    #expect(unnamed.leadName == "@maya_k")
    // And is not printed twice.
    #expect(unnamed.handleLine == nil)
}

@MainActor
@Test func beforeAHandleIsClaimedTheBlockSaysSo() async {
    let model = OwnProfileModel(store: store(handle: { nil }))
    await model.load()
    #expect(model.leadName == "no handle yet")
    #expect(model.handleLine == nil)
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

@MainActor
@Test func yourOwnProfileStatesTheNameAndBioThatAreActuallyPublished() async {
    // Both come from `public_profile`, so the bio is the APPROVED body
    // (tech/02 §3.2). This screen is where you find out what is visible; the
    // settings row is where you see what you typed.
    let model = OwnProfileModel(store: store(profileFor: { _ in
        profile(displayName: "rae", bio: "i rank everything i own.")
    }))
    await model.load()
    #expect(model.displayName == "rae")
    #expect(model.bio == "i rank everything i own.")
}

@MainActor
@Test func anUnpublishedNameAndBioAreAbsentRatherThanEmptyStrings() async {
    // Nil, not "". An empty string would draw an empty line where the frame
    // draws nothing, because `Text("")` still takes its leading.
    let model = OwnProfileModel(store: store())
    await model.load()
    #expect(model.displayName == nil)
    #expect(model.bio == nil)
}

@Test func badgesKeepTheFramesOrderAndItsPerFactTones() {
    // G.Profile: combo (lilac) · fenty 240 (butter) · 3b (mint). The tone
    // tracks the FACT, so dropping the middle one must not slide butter onto
    // the hair pattern.
    let all = ProfileBadgeRow.badges(skinType: "combo", anchor: "fenty 240", hairPattern: "3b")
    #expect(all.map(\.value) == ["combo", "fenty 240", "3b"])
    #expect(all.map(\.tone) == [.lilac, .butter, .mint])

    let gapped = ProfileBadgeRow.badges(skinType: "combo", anchor: nil, hairPattern: "3b")
    #expect(gapped.map(\.value) == ["combo", "3b"])
    #expect(gapped.map(\.tone) == [.lilac, .mint])
}

@Test func anUnpublishedBadgeIsAbsentAndNeverRenderedAsUnknown() {
    // A nil badge means "not published", which `public_profile` deliberately
    // does not distinguish from "has none" — so there is nothing honest to
    // draw in its place. All three off is an empty row, not three blanks.
    #expect(ProfileBadgeRow.badges(skinType: nil, anchor: nil, hairPattern: nil).isEmpty)
}
