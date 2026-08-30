import DataKit
import Foundation
import Testing
@testable import Discover

// GLO-229 — PRD §11's visible taste profile, and the two rules that make it
// safe to show: gate on confidence, and never invert a signed score.

/// 0035's wire shape. `w` and `shrunk_score` are supplied rather than derived
/// so a test can put a row exactly on the wrong side of a boundary.
private func row(_ label: String, n: Int, shrunk: Double) throws -> AffinityRow {
    let raw = Data("""
    {"attribute_chip_id":"\(UUID().uuidString)","label":"\(label)",
     "raw_score":\(shrunk),"n_signals":\(n),
     "w":\(Double(n) / Double(n + 10)),"shrunk_score":\(shrunk)}
    """.utf8)
    return try JSONDecoder().decode(AffinityRow.self, from: raw)
}

@Test func fourLoggedItemsDoNotSpeakAndFiveDo() throws {
    // PRD §11 sets the floor from the failure it guards: "showing a wrong
    // profile at four logged items poisons trust".
    let rows = try [row("fragrance-free", n: 4, shrunk: 0.9), row("dewy", n: 5, shrunk: 0.4)]
    #expect(TasteReceipt.speakable(rows).map(\.label) == ["dewy"])
}

@Test func theConfidenceFloorIsTheSpecsOwnWDressedAsANumber() {
    // tech/01 §8 calls w the gate; w = n/(n+10) is monotone in n, so the two
    // spellings of "five signals" must agree or one of them has drifted.
    #expect(TasteReceipt.minimumSignals == 5)
    #expect(abs(TasteReceipt.minimumConfidence - 5.0 / 15.0) < 0.000_001)
}

@Test func aNegativeRowIsSilentBecauseRenderingItWouldInvertIt() throws {
    // 0035 weights dislike-with-a-chip at −2.0 and bottom-of-list rank
    // negatively, so shrunk_score is SIGNED. "fragrance-free · 12 of your
    // logs" under "what your logs say" would read as a preference for the
    // exact thing the evidence says is avoided.
    let rows = try [
        row("heavily fragranced", n: 20, shrunk: -1.4),
        row("fragrance-free", n: 12, shrunk: 0.8)
    ]
    #expect(TasteReceipt.speakable(rows).map(\.label) == ["fragrance-free"])
}

@Test func zeroIsNotEvidenceEitherWay() throws {
    #expect(try TasteReceipt.speakable([row("flat", n: 30, shrunk: 0)]).isEmpty)
}

@Test func theCardIsCappedSoItStaysACardAndKeepsTheServersOrder() throws {
    let rows = try (1 ... 8).map { try row("a\($0)", n: 10, shrunk: 1.0 - Double($0) / 10) }
    let spoken = TasteReceipt.speakable(rows)
    #expect(spoken.count == TasteReceipt.maximumRows)
    #expect(spoken.map(\.label) == ["a1", "a2", "a3", "a4", "a5"], "0035 already ordered these")
}

// ── the card in the stream ──────────────────────────────────────────────────

private func pick() throws -> DiscoverHit {
    let raw = Data("""
    {"id":"\(UUID().uuidString)","name":"n","brand_name":"b",
     "category_id":"\(UUID().uuidString)","category_slug":"blush","domain":"makeup",
     "scope":"canonical","n_face_offs":null,"variant_label":null,
     "catalog_image_key":null,"catalog_image_width":null,"catalog_image_height":null,
     "basis":"taste","basis_n":3}
    """.utf8)
    return try JSONDecoder().decode(DiscoverHit.self, from: raw)
}

@MainActor
@Test func aVectorThatCannotSpeakPutsNoCardInTheStream() async throws {
    // The seeded state, probed: maya's vector is one row, `fragrance-free`,
    // n_signals = 1, w = 0.091. Correctly silent, not broken.
    let picks = try (1 ... 3).map { _ in try pick() }
    var store = DiscoverStore(feed: { _ in picks }, crosswalk: { _ in [] })
    store.affinity = { try [row("fragrance-free", n: 1, shrunk: 0.02)] }
    let model = DiscoverModel(store: store)
    model.load()
    await model.loadTask?.value
    #expect(model.taste.isEmpty)
    #expect(!model.stream.map(\.id).contains("taste"))
}

@MainActor
@Test func aSpeakingVectorLandsAfterTheCrosswalkAndBeforeTrending() async throws {
    let picks = try (1 ... 6).map { _ in try pick() }
    var store = DiscoverStore(feed: { _ in picks }, crosswalk: { _ in [] })
    store.affinity = { try [row("fragrance-free", n: 12, shrunk: 0.8)] }
    let model = DiscoverModel(store: store)
    model.load()
    await model.loadTask?.value
    let ids = model.stream.map(\.id)
    #expect(ids[4] == "taste")
    let receipt = try #require(ids.firstIndex(of: "taste"))
    let trending = try #require(ids.firstIndex(of: "trending"))
    #expect(receipt < trending)
}

@MainActor
@Test func aFailedVectorReadCostsTheReceiptAndNothingElse() async throws {
    let picks = try [pick()]
    var store = DiscoverStore(feed: { _ in picks }, crosswalk: { _ in [] })
    store.affinity = { throw URLError(.timedOut) }
    let model = DiscoverModel(store: store)
    model.load()
    await model.loadTask?.value
    #expect(model.taste.isEmpty)
    #expect(model.picks.count == 1)
    #expect(model.phase == .loaded)
}

@MainActor
@Test func noAffinitySeamMeansNoCardRatherThanAnEmptyOne() async throws {
    let picks = try [pick()]
    let store = DiscoverStore(feed: { _ in picks }, crosswalk: { _ in [] })
    let model = DiscoverModel(store: store)
    model.load()
    await model.loadTask?.value
    #expect(!model.stream.map(\.id).contains("taste"))
}
