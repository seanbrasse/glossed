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
    live.choose(.match(product))
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
    live.choose(.match(product))
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
    live.query = "l"
    await live.search()
    #expect(live.isMiss == false)
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
