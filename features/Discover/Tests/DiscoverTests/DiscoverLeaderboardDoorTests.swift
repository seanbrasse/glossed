import DataKit
import Foundation
import Testing
@testable import Discover

// `G.Discover`'s `leaderboards →` (GLO-107). Its own file because
// `DiscoverModelTests` sits at the 300-line ceiling — the house remedy.
//
// The door's whole difficulty is that the frame's link names no category
// and `LeaderboardModel` requires one, so these tests are about WHICH
// category the stream hands over, and when it refuses to hand over any.

private func hit(_ name: String, basis: String, n: Int, slug: String) throws -> DiscoverHit {
    // Decoded off the wire shape, like every other Discover fixture: the
    // decoder is part of what is under test.
    let raw = Data("""
    {"id":"\(UUID().uuidString)","name":"\(name)","brand_name":"b",
     "category_id":"\(UUID().uuidString)","category_slug":"\(slug)","domain":"makeup",
     "scope":"canonical","n_face_offs":null,"variant_label":null,
     "catalog_image_key":null,"catalog_image_width":null,"catalog_image_height":null,
     "basis":"\(basis)","basis_n":\(n)}
    """.utf8)
    return try JSONDecoder().decode(DiscoverHit.self, from: raw)
}

@MainActor
private func loaded(_ picks: [DiscoverHit]) async -> DiscoverModel {
    let model = DiscoverModel(store: DiscoverStore(feed: { _ in picks }, crosswalk: { _ in [] }))
    model.load()
    await model.loadTask?.value
    return model
}

@MainActor
@Test func theLeaderboardsDoorOpensAtTheFirstClaimingPickNotTheWander() async throws {
    // The wander leads the feed here, which is the case that would send the
    // boards somewhere arbitrary: it is a deliberate random, so the door
    // skips it for the first pick that actually claims something.
    let model = try await loaded([
        hit("w", basis: "exploration", n: 0, slug: "lip-oil"),
        hit("a", basis: "shade", n: 9, slug: "foundation"),
        hit("b", basis: "taste", n: 3, slug: "cleanser")
    ])
    #expect(model.leaderboardEntry?.categorySlug == "foundation")
}

@MainActor
@Test func aFeedOfNothingButWanderOffersNoLeaderboardsDoor() async throws {
    // Every pick is a wander, so no category here was earned — and a door
    // with no defensible destination is not offered rather than opened on
    // a guess. The row itself still renders; only the link goes.
    let model = try await loaded([hit("w", basis: "exploration", n: 0, slug: "blush")])
    #expect(model.phase == .loaded)
    #expect(model.leaderboardEntry == nil)
}

@MainActor
@Test func anEmptyFeedOffersNoLeaderboardsDoor() async {
    let model = await loaded([])
    #expect(model.leaderboardEntry == nil)
}

@MainActor
@Test func theLeaderboardsDoorCarriesTheDomainTheBoardAlsoNeeds() async throws {
    // `LeaderboardModel` is built from a slug AND a domain; a door carrying
    // only the slug would not open anything.
    let model = try await loaded([hit("a", basis: "popular", n: 12, slug: "mascara")])
    let entry = try #require(model.leaderboardEntry)
    #expect(entry.categorySlug == "mascara")
    #expect(entry.domain == .makeup)
}

@MainActor
@Test func theDoorFollowsTheServersOrderRatherThanPickingAFavourite() async throws {
    // 0040 ranks the picks and the client does not second-guess it — the
    // same rule the stream's composition already follows. Reversing the
    // feed must move the door, or something client-side is choosing.
    let first = try hit("a", basis: "shade", n: 9, slug: "foundation")
    let second = try hit("b", basis: "taste", n: 3, slug: "cleanser")
    #expect(await loaded([first, second]).leaderboardEntry?.categorySlug == "foundation")
    #expect(await loaded([second, first]).leaderboardEntry?.categorySlug == "cleanser")
}
