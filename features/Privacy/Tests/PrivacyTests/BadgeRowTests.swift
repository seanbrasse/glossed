import DataKit
import Foundation
import Testing
@testable import Privacy

// The badge switches, moved here with the code they test (GLO-213). They are
// the only path by which a body fact reaches another person, so they live on
// the privacy screen rather than a second one.

private func badges(
    badges: @escaping @Sendable () async throws -> ProfileBadges = { ProfileBadges() },
    setBadge: @escaping @Sendable (ProfileBadges.Badge, Bool) async throws -> Void = { _, _ in }
) -> BadgeStore {
    BadgeStore(badges: badges, setBadge: setBadge)
}

private func store(
    load: @escaping @Sendable () async throws -> PrivacyScopes = { PrivacyScopes() },
    setScope: @escaping @Sendable (ScopedSurface, PrivacyScope) async throws -> Void = { _, _ in },
    setDiscoverable: @escaping @Sendable (Bool) async throws -> Void = { _ in }
) -> PrivacyStore {
    PrivacyStore(load: load, setScope: setScope, setDiscoverable: setDiscoverable)
}

@MainActor
@Test func everyBadgeStartsOff() async {
    // All three default false. They are the only path by which skin type, the
    // anchor shade and hair pattern reach another human (§3.4).
    let model = PrivacyModel(store: store(), badgeStore: badges())
    await model.load()
    for row in BadgeRow.all {
        #expect(!model.badges.isOn(row.badge))
    }
}

@MainActor
@Test func turningOneBadgeOnLeavesTheOthersOff() async {
    // A write that reset its neighbours would publish Regulated data the user
    // never chose to publish.
    let model = PrivacyModel(store: store(), badgeStore: badges())
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
    let model = PrivacyModel(store: store(), badgeStore: badges(setBadge: { _, _ in throw Boom() }))
    await model.load()
    await model.setBadge(.skinType, on: true)
    #expect(!model.badges.showSkinType)
    #expect(model.errorMessage != nil)
}

@Test func everyBadgeRowSaysWhatItPublishes() {
    // The consequence belongs next to the control, not in a policy nobody
    // opens. Each row names what becomes visible and to whom.
    //
    // The audience check used to look for "profile" or "suggested", because
    // the audience WAS "anyone who can see your profile". Sean's Aug 30
    // ruling (GLO-205) changed who that is — a body fact now reaches only
    // someone it matches — so the proxy is re-specified rather than the copy
    // bent to satisfy a stale one.
    #expect(BadgeRow.all.count == ProfileBadges.Badge.allCases.count)
    for row in BadgeRow.all {
        #expect(row.title == row.title.lowercased())
        #expect(row.detail == row.detail.lowercased())
        #expect(row.detail.contains("people"))
    }
}

@Test func bodyFactRowsPromiseAMatchRatherThanPublication() {
    // GLO-205. The switch may no longer offer to show the value, because the
    // read path no longer returns it — and a control that promises more than
    // public_profile will deliver is how the copy and the query drift apart.
    for row in BadgeRow.all where row.badge != .anchor {
        #expect(row.detail.contains("matches"))
        #expect(!row.detail.contains("sees it."))
    }

    // The anchor is exempt on purpose: a shade you wear is a product you own,
    // not a body fact, and it still appears verbatim.
    let anchor = BadgeRow.all.first { $0.badge == .anchor }
    #expect(anchor?.detail.contains("appears on your profile") == true)
}

@MainActor
@Test func badgeApplicationIsIndependentPerFlag() {
    // Exhaustive: every badge, both directions, leaves the other two alone.
    for badge in ProfileBadges.Badge.allCases {
        let on = PrivacyModel.applying(badge, on: true, to: ProfileBadges())
        #expect(on.isOn(badge))
        for other in ProfileBadges.Badge.allCases where other != badge {
            #expect(!on.isOn(other))
        }
    }
}
