import DataKit
import Foundation
import Testing
@testable import AddLadder

private let goodGTIN = "0810086012343"

@MainActor
private func model(
    known: [String: Variant] = [:],
    availability: ScannerAvailability = .ready
) -> BarcodeRungModel {
    BarcodeRungModel(catalog: FakeVariants(known: known), availability: availability)
}

@MainActor
@Test func aMatchResolvesTheLadderOnAVariant() async throws {
    // Unlike the search rung, a GTIN identifies one shade in one size — so this
    // is the one rung that can finish without a shade pick (GLO-56).
    let found = try variant(gtin: goodGTIN)
    let live = model(known: [goodGTIN: found])
    await live.scanned(goodGTIN)
    #expect(live.ladder.resolution == .matched(variantID: found.id))
    #expect(live.message == nil)
}

@MainActor
@Test func aValidCodeWeDoNotStockAdvancesAndKeepsTheGTIN() async {
    let live = model()
    await live.scanned(goodGTIN)
    #expect(live.ladder.rung == .nearMatches)
    #expect(live.ladder.scannedGTIN == goodGTIN)
}

@MainActor
@Test func aMisreadMovesNothingAndLetsYouTryAgain() async {
    // The ladder must not advance on a bad read: the user has not learned
    // anything about the catalog, and neither have we.
    let live = model()
    await live.scanned("0810086012344")
    #expect(live.ladder.rung == .barcode)
    #expect(live.ladder.scannedGTIN == nil)
    #expect(live.message == "couldn't read that — hold it steadier")
}

@MainActor
@Test func theSameLabelInEveryFrameIsResolvedOnce() async throws {
    // The recognized-items stream re-reports a barcode many times a second.
    let found = try variant(gtin: goodGTIN)
    let catalog = FakeVariants(known: [goodGTIN: found])
    let live = BarcodeRungModel(catalog: catalog)
    for _ in 0 ..< 30 {
        await live.scanned(goodGTIN)
    }
    #expect(await catalog.lookedUp.count == 1)
}

@MainActor
@Test func aMisreadCanBeRetriedBecauseItWasNeverAnAnswer() async {
    let live = model()
    await live.scanned("0810086012344")
    await live.scanned("0810086012344")
    #expect(live.ladder.rung == .barcode)
}

@MainActor
@Test func aFailedLookupIsNotReportedAsAGapInTheCatalog() async {
    // Otherwise the user goes and creates a product we already stock.
    let live = BarcodeRungModel(catalog: FailingVariants())
    await live.scanned(goodGTIN)
    #expect(live.failure?.code == .offline)
    #expect(live.ladder.rung == .barcode)
    #expect(live.ladder.scannedGTIN == nil)
    #expect(live.message == "no connection — try again in a sec.")
}

@MainActor
@Test func aFailedLookupCanBeRetriedWithTheSameCode() async {
    let live = BarcodeRungModel(catalog: FailingVariants())
    await live.scanned(goodGTIN)
    // The label is still in front of the camera; the next frame must try again
    // rather than be swallowed as already-handled.
    await live.scanned(goodGTIN)
    #expect(live.failure != nil)
}

@MainActor
@Test func aRungWithNoCameraIsStillARungYouCanLeave() {
    for blocked in [ScannerAvailability.unsupportedDevice, .permissionDenied] {
        let live = model(availability: blocked)
        #expect(live.isScanning == false)
        #expect(live.message == blocked.explanation)
        #expect(live.escapePrompt == "no camera — find it by photo")
        live.noneOfThese()
        #expect(live.ladder.rung == .nearMatches)
    }
}

@MainActor
@Test func thePhoneThatCannotScanIsToldSomethingDifferentFromThePhoneYouSaidNoTo() {
    // One is recoverable and the other is not, so pointing an unsupported
    // device at Settings would be a wild goose chase.
    #expect(ScannerAvailability.unsupportedDevice.explanation != ScannerAvailability.permissionDenied.explanation)
    #expect(ScannerAvailability.permissionDenied.explanation.contains("settings"))
    #expect(ScannerAvailability.unsupportedDevice.explanation.contains("settings") == false)
}

@MainActor
@Test func scanningStopsOnceTheLadderIsResolved() async throws {
    let found = try variant(gtin: goodGTIN)
    let live = model(known: [goodGTIN: found])
    await live.scanned(goodGTIN)
    #expect(live.isScanning == false)
}
