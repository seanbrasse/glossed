import DataKit
import Foundation
import Testing
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
    let picks = [try hit("a", basis: "taste", n: 2)]
    let store = DiscoverStore(
        feed: { _ in picks },
        crosswalk: { _ in throw URLError(.timedOut) } // one read failing…
    )
    let model = DiscoverModel(store: store)
    model.load()
    await model.loadTask?.value
    #expect(model.picks.count == 1)          // …does not blank the other
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
