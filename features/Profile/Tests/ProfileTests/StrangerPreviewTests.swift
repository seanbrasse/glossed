import DataKit
import Foundation
import Testing
@testable import Profile

private func profile(skin: String? = "combo", anchor: String? = "fenty beauty 220") -> PublicProfile {
    let skinJSON = skin.map { "\"\($0)\"" } ?? "null"
    let anchorJSON = anchor.map { "\"\($0)\"" } ?? "null"
    let json = Data("""
    {"handle":"maya_k","display_name":"maya","avatar_seed":null,"bio":null,
     "badge_skin_type":\(skinJSON),"badge_anchor":\(anchorJSON),"badge_hair_pattern":null,
     "followers":0,"following":0,"shelf_n":7,"ranked_lists_n":1,
     "shelf_visible":true,"rankings_visible":true,"routines_visible":true}
    """.utf8)
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PublicProfile.self, from: json)
}

@Test func theOwnersOwnVisibilityFlagsAreIgnored() {
    // THE WHOLE POINT. can_view short-circuits when viewer = owner, so
    // public_profile called on yourself returns shelf_visible = true even when
    // the scope is only_you. Building the preview on those flags would claim a
    // stranger sees a private shelf — the defect this screen exists to catch.
    let preview = StrangerPreview(
        profile: profile(), // every visible flag is true
        scopes: PrivacyScopes(), // every scope is only_you
        badges: ProfileBadges()
    )
    #expect(!preview.shelfVisible)
    #expect(!preview.rankingsVisible)
    #expect(!preview.routinesVisible)
}

@Test func friendsIsNotAStranger() {
    // The distinction three scopes exist for. A friends-scoped surface must
    // read as hidden here, or the preview overstates exposure.
    let preview = StrangerPreview(
        profile: profile(),
        scopes: PrivacyScopes(shelf: .friends, rankings: .publicScope),
        badges: ProfileBadges()
    )
    #expect(!preview.shelfVisible)
    #expect(preview.rankingsVisible)
}

@Test func aFriendsSurfaceIsNamedRatherThanPreviewed() {
    // friends needs a real mutual follow to mean anything; faking one would be
    // its own lie. Naming what a follower additionally sees is the honest
    // version.
    let preview = StrangerPreview(
        profile: profile(), scopes: PrivacyScopes(shelf: .friends), badges: ProfileBadges()
    )
    #expect(preview.friendsOnlySurfaces == ["shelf"])
}

@Test func unpublishedBadgesDoNotAppear() {
    // The profile row carries the values; the flags decide whether a stranger
    // sees them. Rendering the values without checking the flags would publish
    // Regulated data nobody opted into.
    let preview = StrangerPreview(
        profile: profile(), scopes: PrivacyScopes(), badges: ProfileBadges()
    )
    #expect(preview.skinType == nil)
    #expect(preview.anchor == nil)
}

@Test func publishedBadgesDoAppear() {
    let preview = StrangerPreview(
        profile: profile(),
        scopes: PrivacyScopes(),
        badges: ProfileBadges(showSkinType: true, showAnchor: false)
    )
    #expect(preview.skinType == "combo")
    #expect(preview.anchor == nil)
}

@Test func aBadgeFlagWithNoValueStaysEmpty() {
    // Opted in, but nothing to show — an anchor needs a worn shade. Must not
    // render an empty badge.
    let preview = StrangerPreview(
        profile: profile(anchor: nil),
        scopes: PrivacyScopes(),
        badges: ProfileBadges(showAnchor: true)
    )
    #expect(preview.anchor == nil)
}

@Test func theAllPrivateCaseIsRecognised() {
    let preview = StrangerPreview(
        profile: profile(), scopes: PrivacyScopes(), badges: ProfileBadges()
    )
    #expect(preview.nothingIsPublic)
}

@Test func anythingPublicClearsTheAllPrivateCase() {
    let preview = StrangerPreview(
        profile: profile(), scopes: PrivacyScopes(shelf: .publicScope), badges: ProfileBadges()
    )
    #expect(!preview.nothingIsPublic)
}

@MainActor
@Test func noHandleMeansNothingToPreview() async {
    let model = StrangerPreviewModel(store: StrangerPreviewStore(
        handle: { nil }, profile: { _ in nil },
        scopes: { PrivacyScopes() }, badges: { ProfileBadges() }
    ))
    await model.load()
    #expect(model.needsHandle)
    #expect(model.preview == nil)
}
