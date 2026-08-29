import DataKit
import Foundation
import Testing
import Tracking
@testable import Discover

// The model against a recording stub — the ShelfChips test shape.

private func hit(_ name: String, basis: String, n: Int) throws -> DiscoverHit {
    let raw = Data("""
    {"id":"\(UUID().uuidString)","name":"\(name)","brand_name":"b",
     "category_id":"\(UUID().uuidString)","category_slug":"blush","domain":"makeup",
     "scope":"canonical","n_face_offs":null,"variant_label":null,
     "catalog_image_key":null,"catalog_image_width":null,"catalog_image_height":null,
     "basis":"\(basis)","basis_n":\(n)}
    """.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .useDefaultKeys
    return try decoder.decode(DiscoverHit.self, from: raw)
}

@MainActor
@Test func loadFillsBothSectionsIndependently() async throws {
    let picks = try [hit("a", basis: "taste", n: 2)]
    let store = DiscoverStore(
        feed: { _ in picks },
        crosswalk: { _ in throw URLError(.timedOut) } // one read failing…
    )
    let model = DiscoverModel(store: store)
    model.load()
    await model.loadTask?.value
    #expect(model.picks.count == 1) // …does not blank the other
    #expect(model.crosswalk.isEmpty)
    #expect(model.phase == .loaded)
}

@MainActor
@Test func bothEmptyIsTheEmptyPhaseNotABlankScreen() async {
    let store = DiscoverStore(feed: { _ in [] }, crosswalk: { _ in [] })
    let model = DiscoverModel(store: store)
    model.load()
    await model.loadTask?.value
    #expect(model.phase == .empty)
}

@MainActor
@Test func noStoreDegradesToEmptyNotACrash() {
    let model = DiscoverModel(store: nil)
    model.load()
    #expect(model.phase == .empty)
}

@Test func everyBasisHasWordsAndOnlyTheWanderClaimsNothing() {
    // The copy rules, asserted: every basis renders words; every basis that
    // makes a claim has an evidence label naming whose n it is; exploration
    // alone claims nothing (a zero would read as a failed claim).
    for basis in [DiscoverHit.Basis.taste, .shade, .everyone, .popular, .exploration] {
        #expect(!DiscoverModel.basisLine(basis).isEmpty)
    }
    #expect(DiscoverModel.evidenceLabel(.taste) == "of your logs")
    #expect(DiscoverModel.evidenceLabel(.shade)?.contains("your shade") == true)
    #expect(DiscoverModel.evidenceLabel(.everyone)?.contains("everyone") == true)
    #expect(DiscoverModel.evidenceLabel(.exploration) == nil)
}

@MainActor
@Test func imageURLComposesFromBaseAndDegradesToNil() throws {
    let pick = try hit("x", basis: "popular", n: 6)
    let based = DiscoverModel(store: nil, imageBase: URL(string: "https://s.test/catalog"))
    let bare = DiscoverModel(store: nil)
    #expect(based.imageURL(for: pick.hit) == nil) // no key → mock, never broken
    #expect(bare.imageURL(for: pick.hit) == nil)
}

// ── the events (GLO-20's last acceptance row) ───────────────────────────────

private actor CapturingPoster: EventPosting {
    private(set) var posted: [QueuedEvent] = []
    func post(_ batch: [QueuedEvent]) async throws {
        posted.append(contentsOf: batch)
    }
}

@Test func slotsFollowTheStageVocabulary() {
    // taste is the Stage-1 pick; the population tiers are stage0; the wander
    // names itself. A new basis fails here before it misfiles an event.
    #expect(DiscoverModel.slot(for: .taste) == .picked)
    #expect(DiscoverModel.slot(for: .shade) == .stage0)
    #expect(DiscoverModel.slot(for: .everyone) == .stage0)
    #expect(DiscoverModel.slot(for: .popular) == .stage0)
    #expect(DiscoverModel.slot(for: .exploration) == .exploration)
}

@MainActor
@Test func aLoadFiresOneImpressionPerRowShown() async throws {
    let picks = try [hit("a", basis: "taste", n: 1), hit("b", basis: "exploration", n: 0)]
    let poster = CapturingPoster()
    let tracker = Tracker(poster: poster)
    let model = DiscoverModel(
        store: DiscoverStore(feed: { _ in picks }, crosswalk: { _ in [] }),
        tracker: tracker
    )
    model.load()
    await model.loadTask?.value
    // the impression task is fire-and-forget; give it one hop, then flush
    await Task.yield()
    try await Task.sleep(for: .milliseconds(50))
    await tracker.flush()
    let names = await poster.posted.map(\.name)
    #expect(names.filter { $0 == "rec_impression" }.count == 2)
}

// ── the dismissal (GLO-181's client half) ───────────────────────────────────

@MainActor
@Test func aDismissalLeavesOptimisticallyAndReportsWhatWasSent() async throws {
    let pick = try hit("gone", basis: "taste", n: 1)
    let kept = try hit("stays", basis: "popular", n: 6)
    actor Written { var rows: [(UUID, String?)] = []; func add(_ row: (UUID, String?)) {
        rows.append(row)
    } }
    let written = Written()
    let poster = CapturingPoster()
    let tracker = Tracker(poster: poster)
    let model = DiscoverModel(
        store: DiscoverStore(
            feed: { _ in [pick, kept] },
            crosswalk: { _ in [] },
            dismiss: { id, reason in await written.add((id, reason)) }
        ),
        tracker: tracker
    )
    model.load()
    await model.loadTask?.value
    model.dismiss(pick, reason: "not_for_me")
    #expect(model.picks == [kept]) // gone before the write returns
    await model.dismissTask?.value
    try await Task.sleep(for: .milliseconds(50))
    await tracker.flush()
    // the sweep session's lesson: assert what was SENT, not that something was
    let row = try #require(await written.rows.first)
    #expect(row.0 == pick.hit.id)
    #expect(row.1 == "not_for_me")
    let dismissed = await poster.posted.filter { $0.name == "rec_dismissed" }
    #expect(dismissed.count == 1)
}

@MainActor
@Test func aFailedDismissalPutsTheRowBack() async throws {
    let pick = try hit("bounces", basis: "taste", n: 1)
    let model = DiscoverModel(
        store: DiscoverStore(
            feed: { _ in [pick] },
            crosswalk: { _ in [] },
            dismiss: { _, _ in throw URLError(.timedOut) }
        )
    )
    model.load()
    await model.loadTask?.value
    model.dismiss(pick, reason: nil)
    #expect(model.picks.isEmpty)
    await model.dismissTask?.value
    #expect(model.picks == [pick]) // the fit-section contract
}

@MainActor
@Test func noWritePathMeansNoGesture() {
    let model = DiscoverModel(store: DiscoverStore(feed: { _ in [] }, crosswalk: { _ in [] }))
    #expect(!model.supportsDismissal) // an editor that writes nowhere is not offered
}
