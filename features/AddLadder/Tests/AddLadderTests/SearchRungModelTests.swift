import DataKit
import Foundation
import Testing
@testable import AddLadder

@MainActor
private func model(hits: [CatalogHit] = [], failure: GlossedError? = nil) -> SearchRungModel {
    SearchRungModel(catalog: FakeCatalog(hits: hits, failure: failure))
}

@MainActor
@Test func theWayOutIsAlwaysTheLastOptionEvenWithNoResults() {
    let live = model()
    #expect(live.options.count == 1)
    #expect(live.options.last?.id == "none-of-these")
}

@MainActor
@Test func theWayOutStaysInTheSameListAsTheMatches() async throws {
    let live = try model(hits: [hit(name: "Watermelon Glow"), hit(name: "Dew Drops")])
    live.query = "glow"
    await live.search()
    #expect(live.options.count == 3)
    #expect(live.options.last?.id == "none-of-these")
}

@MainActor
@Test func theEscapePromptNamesWhereItGoesWhenThereIsNothingToPick() async {
    let live = model()
    live.query = "laneige"
    await live.search()
    #expect(live.options.last == .noneOfThese(prompt: "none of these — scan the barcode"))
}

@MainActor
@Test func theEscapePromptStillNamesWhereItGoesWhenThereAreMatches() async throws {
    // The frame writes one label for this rung. Shortening it once results
    // arrive drops the "scan the barcode" from the only moment it is a real
    // choice: matches on screen and none of them the thing in your hand.
    let live = try model(hits: [hit(name: "Watermelon Glow")])
    live.query = "glow"
    await live.search()
    #expect(live.options.last == .noneOfThese(prompt: "none of these — scan the barcode"))
}

@MainActor
@Test func choosingTheWayOutAdvancesTheLadder() {
    let live = model()
    live.choose(.noneOfThese(prompt: "none of these"))
    #expect(live.ladder.rung == .barcode)
}

@MainActor
@Test func choosingAMatchOpensTheShadePickRatherThanResolving() async throws {
    // search_catalog returns products.id, and a shelf item is a variant.
    // Resolving here would put the wrong row on someone's shelf.
    let product = try hit(name: "Watermelon Glow")
    let live = model(hits: [product])
    live.query = "glow"
    await live.search()
    live.choose(.match(product, reason: nil))
    #expect(live.pickedProductID == product.id)
    #expect(live.ladder.resolution == nil)

    live.pickedVariant(product.id)
    #expect(live.ladder.isResolved)
}

@MainActor
@Test func backingOutOfTheShadePickLeavesTheUserOnTheSearchRung() async throws {
    let product = try hit(name: "Watermelon Glow")
    let live = model(hits: [product])
    live.query = "glow"
    await live.search()
    live.choose(.match(product, reason: nil))
    live.cancelVariantPick()
    #expect(live.pickedProductID == nil)
    #expect(live.ladder.rung == .search)
    #expect(live.query == "glow")
}

@MainActor
@Test func aFailedSearchIsNeverPresentedAsAnEmptyCatalog() async {
    // Otherwise the user goes and creates a product that already exists.
    let live = model(failure: GlossedError(.offline, userMessage: "no connection — try again in a sec."))
    live.query = "laneige"
    await live.search()
    #expect(live.failure?.code == .offline)
    #expect(live.isMiss == false)
}

@MainActor
@Test func theModelDoesNotCallAMissWhenTheUserIsStillTyping() async {
    let live = model()
    for stillTyping in ["l", " a ", "  ", "\tb"] {
        // Whitespace is why the model must not re-derive this from query.count:
        // " a " is three characters and one letter. The rung tidies before it
        // decides, so the rung's verdict is the only one.
        live.query = stillTyping
        await live.search()
        #expect(live.isMiss == false, "\"\(stillTyping)\" is typing, not a miss")
    }
}

@MainActor
@Test func aRealEmptySearchIsAMiss() async {
    let live = model()
    live.query = "laneige lip sleeping mask"
    await live.search()
    #expect(live.isMiss)
}

@MainActor
@Test func typingKeepsTheLadderOnTheSearchRung() {
    let live = model()
    live.query = "gl"
    live.query = "glow"
    #expect(live.ladder.rung == .search)
    #expect(live.ladder.query == "glow")
}

// MARK: - GLO-179: the retry the hint promises

/// Fails the first call and succeeds after, so a *retry* can be told apart from
/// a first attempt. `FakeCatalog` is all-or-nothing by design and cannot.
actor FlakyCatalog: CatalogSearching {
    private let hits: [CatalogHit]
    private(set) var calls = 0

    init(hits: [CatalogHit]) {
        self.hits = hits
    }

    func search(_: String, limit _: Int) async throws(GlossedError) -> [CatalogHit] {
        calls += 1
        if calls == 1 {
            throw GlossedError(.offline, userMessage: "no connection — try again in a sec.")
        }
        return hits
    }

    func recordFailedSearch(_: String, domain _: Domain?) async {}
}

@MainActor
@Test func aFailedSearchCanBeRetriedIntoAnAnswer() async throws {
    // `failure != nil` is the exact condition the retry button is gated on, so
    // this pins the affordance's predicate even though the button itself lives
    // in the view. The recovery always existed — editing the query re-ran the
    // search — but nothing on screen said so, and two sibling failure states
    // hand you a button.
    let catalog = try FlakyCatalog(hits: [hit(name: "watermelon glow")])
    let live = SearchRungModel(catalog: catalog, query: "watermelon")

    await live.search()
    #expect(live.failure != nil, "the button appears")
    #expect(live.options.count == 1, "the way out, and nothing dressed up as a result")

    await live.search()
    #expect(live.failure == nil, "the button goes away")
    #expect(await catalog.calls == 2, "a retry is a second ask, not a replayed answer")
    #expect(live.options.count == 2, "one hit plus the way out")
}
