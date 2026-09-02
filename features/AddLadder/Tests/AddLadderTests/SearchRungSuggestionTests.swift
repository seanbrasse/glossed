import DataKit
import Foundation
import Testing
@testable import AddLadder

// MARK: - Suggestions before a letter is typed (GLO-108)

private struct FakeSuggesting: LadderSuggesting {
    let rows: [LadderSuggestion]
    func suggestions(limit _: Int) async throws -> [LadderSuggestion] {
        rows
    }
}

private func discoverHit(name: String, basis: String, basisN: Int) throws -> DiscoverHit {
    let json = """
    {"id":"\(UUID().uuidString)","name":"\(name)","brand_name":"Glow Recipe",
     "category_id":"\(UUID().uuidString)",
     "category_slug":"serum","domain":"skincare","scope":"canonical",
     "basis":"\(basis)","basis_n":\(basisN)}
    """
    return try JSONDecoder().decode(DiscoverHit.self, from: Data(json.utf8))
}

@MainActor
@Test func anEmptyQueryOffersSuggestionsEachWithItsReasonAndN() async throws {
    let row = try LadderSuggestion(hit: hit(name: "Watermelon Glow"), n: 14, reason: "people in your shade kept it")
    let live = SearchRungModel(catalog: FakeCatalog(hits: []), suggestions: FakeSuggesting(rows: [row]))
    await live.search()
    #expect(live.isShowingSuggestions)
    #expect(live.options.count == 2, "the suggestion, then the way out")
    #expect(live.options.first == .match(row.hit, reason: "14 people in your shade kept it"))
    #expect(live.options.last?.id == "none-of-these")
}

@MainActor
@Test func theFirstLetterHandsTheListBackToTheCatalog() async throws {
    let row = try LadderSuggestion(hit: hit(name: "Watermelon Glow"), n: 14, reason: "people in your shade kept it")
    let match = try hit(name: "Dew Drops")
    let live = SearchRungModel(catalog: FakeCatalog(hits: [match]), suggestions: FakeSuggesting(rows: [row]))
    await live.search()
    live.query = "dew"
    await live.search()
    #expect(!live.isShowingSuggestions)
    #expect(live.options.first == .match(match, reason: nil))
}

@MainActor
@Test func withNoSuggesterTheRungOpensOnTheFieldAlone() async {
    let live = SearchRungModel(catalog: FakeCatalog(hits: []))
    await live.search()
    #expect(!live.isShowingSuggestions)
    #expect(live.options.count == 1)
}

@Test func aWanderIsOfferedButClaimsNothing() throws {
    // `.exploration` carries basis_n 0 by construction. It stays on the
    // list — on thin data it is the whole feed — and prints no n, because
    // a number it does not have would be a claim it cannot make.
    let wander = try LadderSuggestion(hit: discoverHit(name: "x", basis: "exploration", basisN: 0))
    #expect(wander.line == "a wander — no evidence, just curiosity")
    let shade = try LadderSuggestion(hit: discoverHit(name: "y", basis: "shade", basisN: 9))
    #expect(shade.line == "9 people in your shade kept it")
}
