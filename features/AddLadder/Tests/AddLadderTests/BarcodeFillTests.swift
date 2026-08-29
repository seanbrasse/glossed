import DataKit
import Foundation
import Testing
@testable import AddLadder

// GLO-93's client half: a scanned miss gets one fill attempt, and every way
// that attempt can go wrong leaves the ladder exactly as it was.

private struct StubFill: BarcodeFilling {
    let answer: BarcodeFillSuggestion?
    func suggestion(gtin _: String) async -> BarcodeFillSuggestion? {
        answer
    }
}

private func suggestion(name: String = "niacinamide 10% + zinc") -> BarcodeFillSuggestion {
    BarcodeFillSuggestion(
        found: true, brand: "the ordinary", name: name,
        domain: "skincare", inci: "niacinamide, zinc pca"
    )
}

private actor MissingCatalog: VariantLookup {
    func variant(gtin _: String) async throws(GlossedError) -> Variant? {
        nil
    }
}

@MainActor
@Test func aFilledMissCarriesTheNameToTheCreateRung() async {
    let model = BarcodeRungModel(
        catalog: MissingCatalog(),
        fill: StubFill(answer: suggestion())
    )

    await model.scanned("0769915195941")

    #expect(model.suggestion?.brand == "the ordinary")
    #expect(model.suggestion?.domain == "skincare")
    // The name rides `query` — the seam the create rung already reads.
    #expect(model.ladder.query == "niacinamide 10% + zinc")
    #expect(model.ladder.scannedGTIN == "0769915195941")
    #expect(model.message == "found it — details carried forward")
}

@MainActor
@Test func anUnwiredFillLeavesTheRungExactlyAsItWas() async {
    // Fixture states and undeployed environments: no fill, no change.
    let model = BarcodeRungModel(catalog: MissingCatalog())

    await model.scanned("0769915195941")

    #expect(model.suggestion == nil)
    #expect(model.ladder.query.isEmpty)
    #expect(model.message == "not in the catalog yet — noted")
    // The miss still advances: a fill is a courtesy, not the path.
    #expect(model.ladder.scannedGTIN == "0769915195941")
}

@MainActor
@Test func aFillWithNothingToSayIsTheOldBehaviour() async {
    let model = BarcodeRungModel(catalog: MissingCatalog(), fill: StubFill(answer: nil))

    await model.scanned("0769915195941")

    #expect(model.suggestion == nil)
    #expect(model.ladder.query.isEmpty)
    #expect(model.message == "not in the catalog yet — noted")
}

@MainActor
@Test func oneScanCostsOneFillHoweverManyFramesReportIt() async {
    // The recognized-items stream re-reports the same code many times a
    // second. The rung's dedupe already covered the catalog lookup; the
    // fill rides inside it, which is what keeps a scan at ONE budgeted
    // upstream call (GLO-93's budget is 95/month — a per-frame fill would
    // spend the month on a single product).
    actor Counter: BarcodeFilling {
        private(set) var calls = 0
        func suggestion(gtin _: String) async -> BarcodeFillSuggestion? {
            calls += 1
            return nil
        }

        func count() -> Int {
            calls
        }
    }
    let counter = Counter()
    let model = BarcodeRungModel(catalog: MissingCatalog(), fill: counter)

    for _ in 0 ..< 30 {
        await model.scanned("0769915195941")
    }

    #expect(await counter.count() == 1)
}

@Test func aSuggestionDecodesTheFunctionsOwnShape() throws {
    // The wire contract with supabase/functions/barcode_fill: if these keys
    // drift the fill silently stops filling, so they are spelled out.
    let raw = Data(#"""
    {"found":true,"brand":"The Ordinary","name":"Niacinamide 10% + Zinc 1%",
     "domain":"skincare","inci":"Niacinamide 10.0%, Zinc PCA 1.0%"}
    """#.utf8)
    let decoded = try JSONDecoder().decode(BarcodeFillSuggestion.self, from: raw)
    #expect(decoded.found)
    #expect(decoded.brand == "The Ordinary")
    #expect(decoded.domain == "skincare")
    #expect(decoded.inci == "Niacinamide 10.0%, Zinc PCA 1.0%")
}

@Test func aMissDecodesAsNotFound() throws {
    // The function answers 200 with {found:false} for 404s, budget
    // exhaustion, and a missing key alike — all "nothing to add".
    let decoded = try JSONDecoder().decode(
        BarcodeFillSuggestion.self,
        from: Data(#"{"found":false,"reason":"budget_exhausted"}"#.utf8)
    )
    #expect(!decoded.found)
    #expect(decoded.brand == nil)
}
