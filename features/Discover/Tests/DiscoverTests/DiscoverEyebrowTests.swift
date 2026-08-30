import DataKit
import Foundation
import Testing
@testable import Discover

// GLO-226 — `G.Discover`'s per-cell `<Eyebrow>{c.type}</Eyebrow>`, and the
// rule that keeps it honest: the CATALOG's label or nothing.

private func hit(slug: String) throws -> DiscoverHit {
    let raw = Data("""
    {"id":"\(UUID().uuidString)","name":"n","brand_name":"b",
     "category_id":"\(UUID().uuidString)","category_slug":"\(slug)","domain":"skincare",
     "scope":"canonical","n_face_offs":null,"variant_label":null,
     "catalog_image_key":null,"catalog_image_width":null,"catalog_image_height":null,
     "basis":"taste","basis_n":3}
    """.utf8)
    return try JSONDecoder().decode(DiscoverHit.self, from: raw)
}

/// The three real rows where the slug and the label part company — probed
/// against the local catalog, not invented: `eye` is labelled "eye care",
/// `serum` "serums + actives", `styler` "stylers". They are the whole reason
/// the eyebrow is read rather than derived.
private func category(slug: String, label: String) throws -> DataKit.Category {
    let raw = Data("""
    {"id":"\(UUID().uuidString)","domain":"skincare","slug":"\(slug)","label":"\(label)",
     "wear_in_days":0,"is_anchor":false,"rank_unlock_min":2}
    """.utf8)
    return try JSONDecoder().decode(DataKit.Category.self, from: raw)
}

private func partner(n: Int) throws -> CrosswalkHit {
    let raw = Data("""
    {"id":"\(UUID().uuidString)","name":"p","brand_name":"b",
     "category_id":"\(UUID().uuidString)","category_slug":"serum","domain":"skincare",
     "scope":"canonical","n_face_offs":null,"variant_label":null,
     "catalog_image_key":null,"catalog_image_width":null,"catalog_image_height":null,
     "anchor_variant_id":"\(UUID().uuidString)","anchor_label":"fenty 240","n":\(n)}
    """.utf8)
    return try JSONDecoder().decode(CrosswalkHit.self, from: raw)
}

@MainActor
@Test func theEyebrowIsTheCatalogsLabelNeverTheSlug() async throws {
    let picks = try [hit(slug: "serum")]
    var store = DiscoverStore(feed: { _ in picks }, crosswalk: { _ in [] })
    store.categories = { try [category(slug: "serum", label: "serums + actives")] }
    let model = DiscoverModel(store: store)
    model.load()
    await model.loadTask?.value

    // "serums + actives", not "serum" — a de-hyphenated slug would have been
    // catalog copy this client invented.
    #expect(model.categoryEyebrow(for: picks[0].hit) == "serums + actives")
}

@MainActor
@Test func noCategoriesReadMeansNoEyebrowRatherThanAGuess() async throws {
    let picks = try [hit(slug: "eye")]
    let store = DiscoverStore(feed: { _ in picks }, crosswalk: { _ in [] })
    let model = DiscoverModel(store: store)
    model.load()
    await model.loadTask?.value
    #expect(model.categoryEyebrow(for: picks[0].hit) == nil)
}

@MainActor
@Test func aCategoriesFailureCostsTheEyebrowAndNothingElse() async throws {
    let picks = try [hit(slug: "eye")]
    let partners = try [partner(n: 4)]
    var store = DiscoverStore(feed: { _ in picks }, crosswalk: { _ in partners })
    store.categories = { throw URLError(.timedOut) }
    let model = DiscoverModel(store: store)
    model.load()
    await model.loadTask?.value

    #expect(model.categoryEyebrow(for: picks[0].hit) == nil)
    #expect(model.picks.count == 1, "chrome never costs the screen its picks")
    #expect(model.crosswalk.count == 1)
    #expect(model.phase == .loaded)
}

@MainActor
@Test func aSlugTheReadDidNotCoverRendersNothing() async throws {
    let picks = try [hit(slug: "toner")]
    var store = DiscoverStore(feed: { _ in picks }, crosswalk: { _ in [] })
    store.categories = { try [category(slug: "serum", label: "serums + actives")] }
    let model = DiscoverModel(store: store)
    model.load()
    await model.loadTask?.value
    #expect(model.categoryEyebrow(for: picks[0].hit) == nil)
}
