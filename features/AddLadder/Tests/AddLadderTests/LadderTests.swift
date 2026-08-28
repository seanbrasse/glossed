import Foundation
import Testing
@testable import AddLadder

@Test func noneOfTheseAdvancesFromEveryRungThatOffersIt() {
    // The ticket's first acceptance criterion, as an invariant rather than a
    // per-screen review note: no rung that shows candidates is a dead end.
    for rung in Rung.allCases where rung.offersNoneOfThese {
        var ladder = Ladder(entry: rung)
        ladder.noneOfThese()
        #expect(ladder.rung > rung)
    }
}

@Test func theLadderWalksSearchToConfirmWithoutSkippingARung() {
    var ladder = Ladder()
    #expect(ladder.rung == .search)
    ladder.noneOfThese()
    #expect(ladder.rung == .barcode)
    ladder.noneOfThese()
    #expect(ladder.rung == .nearMatches)
    ladder.noneOfThese()
    #expect(ladder.rung == .create)
    #expect(ladder.trail == [.search, .barcode, .nearMatches, .create])
}

@Test func enteringAtTheBarcodeRungDoesNotInventASearchStep() {
    // Barcode is the pushed path, so the rail must not imply the user skipped
    // something they were never shown.
    var ladder = Ladder(entry: .barcode)
    ladder.noneOfThese()
    #expect(ladder.trail == [.barcode, .nearMatches])
}

@Test func theQueryIsCarriedDownTheLadder() {
    var ladder = Ladder(query: "  glow   recipe  ")
    #expect(ladder.query == "glow recipe")
    ladder.noneOfThese()
    ladder.noneOfThese()
    #expect(ladder.rung == .nearMatches)
    #expect(ladder.query == "glow recipe")
}

@Test func refiningTheQueryDoesNotMoveTheLadder() {
    var ladder = Ladder(query: "glow")
    ladder.refine(query: "glow recipe")
    #expect(ladder.rung == .search)
    #expect(ladder.query == "glow recipe")
    #expect(ladder.trail == [.search])
}

@Test func aMissedScanKeepsTheGTINAndKeepsGoing() {
    var ladder = Ladder(entry: .barcode)
    ladder.scanMissed(gtin: "0123456789012")
    #expect(ladder.rung == .nearMatches)
    #expect(ladder.scannedGTIN == "0123456789012")
}

@Test func aScanOutsideTheBarcodeRungIsIgnored() {
    var ladder = Ladder()
    ladder.scanMissed(gtin: "0123456789012")
    #expect(ladder.rung == .search)
    #expect(ladder.scannedGTIN == nil)
}

@Test func matchingResolvesTheLadderWhereverItHappened() {
    let variant = UUID()
    for rung in Rung.allCases where rung.offersNoneOfThese {
        var ladder = Ladder(entry: rung)
        ladder.matched(variantID: variant)
        #expect(ladder.resolution == .matched(variantID: variant))
        #expect(ladder.isResolved)
        #expect(!ladder.canAdvance)
    }
}

@Test func creatingLandsOnTheConfirmationThatStatesTheDeal() {
    // The personal-scope badge lives on the confirm rung, so creation must not
    // be able to resolve without arriving there.
    let product = UUID()
    var ladder = Ladder(entry: .create, query: "hand cream")
    ladder.created(productID: product)
    #expect(ladder.rung == .confirm)
    #expect(ladder.resolution == .created(productID: product))
    #expect(ladder.trail.last == .confirm)
}

@Test func aResolvedLadderStopsAccepting() {
    var ladder = Ladder()
    let first = UUID()
    ladder.matched(variantID: first)
    ladder.noneOfThese()
    ladder.refine(query: "something else")
    ladder.matched(variantID: UUID())
    #expect(ladder.rung == .search)
    #expect(ladder.query.isEmpty)
    #expect(ladder.resolution == .matched(variantID: first))
}

@Test func onlyTheConfirmRungIsTerminal() {
    for rung in Rung.allCases {
        #expect((rung.next == nil) == (rung == .confirm))
    }
}
