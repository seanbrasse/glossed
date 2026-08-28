import DataKit
import Foundation
import Testing
@testable import AddLadder

/// A real GS1-valid GTIN-13, matching what `supabase/seed.sql` now carries.
private let seededGTIN = "0810086012343"

private func variant(gtin: String) throws -> Variant {
    let json = """
    {"id":"40000000-0000-0000-0000-000000000001",
     "product_id":"30000000-0000-0000-0000-000000000001",
     "shade_code":"220","shade_hex":"#E0B891","size_ml":32,
     "gtin":"\(gtin)","height_mm":110,"price_cents":4000}
    """
    return try JSONDecoder().decode(Variant.self, from: Data(json.utf8))
}

private actor FakeVariants: VariantLookup {
    private let known: [String: Variant]
    private(set) var lookedUp: [String] = []

    init(known: [String: Variant] = [:]) {
        self.known = known
    }

    func variant(gtin: String) async throws(GlossedError) -> Variant? {
        lookedUp.append(gtin)
        return known[gtin]
    }
}

@Test func aScanThatMatchesResolvesToAVariant() async throws {
    let known = try variant(gtin: seededGTIN)
    let catalog = FakeVariants(known: [seededGTIN: known])
    let outcome = try await BarcodeRung(catalog: catalog).resolve(scanned: seededGTIN)
    #expect(outcome == .matched(known))
}

@Test func aValidCodeWeDoNotStockIsDemand() async throws {
    let catalog = FakeVariants()
    let outcome = try await BarcodeRung(catalog: catalog).resolve(scanned: seededGTIN)
    #expect(outcome == .unknownCode(seededGTIN))
}

@Test func aMisreadIsNeverMistakenForAMissingProduct() async throws {
    // One digit off is a bad read, not a gap in the catalog. Recording it as
    // demand would put a code nobody can act on into the queue that decides
    // what we go and add next.
    let catalog = FakeVariants()
    let outcome = try await BarcodeRung(catalog: catalog).resolve(scanned: "0810086012344")
    #expect(outcome == .misread)
    #expect(await catalog.lookedUp.isEmpty)
}

@Test func aQRCodeOnThePackagingIsNotAProductCode() async throws {
    let catalog = FakeVariants()
    for payload in ["https://rarebeauty.com/soft-pinch", "", "   ", "abc123", "12345"] {
        #expect(try await BarcodeRung(catalog: catalog).resolve(scanned: payload) == .misread)
    }
    #expect(await catalog.lookedUp.isEmpty)
}

@Test func surroundingWhitespaceFromTheScannerIsTolerated() async throws {
    let known = try variant(gtin: seededGTIN)
    let catalog = FakeVariants(known: [seededGTIN: known])
    let outcome = try await BarcodeRung(catalog: catalog).resolve(scanned: " \(seededGTIN)\n")
    #expect(outcome == .matched(known))
}

@Test func theCheckDigitIsTheRealGS1One() {
    // Known-good codes from three different GS1 lengths.
    #expect(GTIN.isCheckDigitValid("0810086012343")) // EAN-13
    #expect(GTIN.isCheckDigitValid("036000291452")) // UPC-A
    #expect(GTIN.isCheckDigitValid("96385074")) // EAN-8
    #expect(GTIN.isCheckDigitValid("0810086012340") == false)
}

@Test func everySingleDigitMisreadIsCaught() {
    // The property that makes the misread/miss distinction worth having: the
    // mod-10 digit catches any one wrong digit, which is the common failure.
    let digits = Array(seededGTIN)
    for position in digits.indices {
        for replacement in "0123456789" where replacement != digits[position] {
            var corrupted = digits
            corrupted[position] = replacement
            #expect(
                GTIN.isCheckDigitValid(String(corrupted)) == false,
                "a wrong digit at \(position) should not check out"
            )
        }
    }
}

@Test func theCodeIsNotPaddedBecauseTheStoredSideIsNot() {
    // Padding to GTIN-14 is the right canonical form and the wrong thing to do
    // unilaterally: the lookup is an exact match against whatever the feed
    // supplied. GLO-58 normalizes both sides.
    #expect(GTIN.normalize(seededGTIN) == seededGTIN)
    #expect(GTIN.normalize("036000291452") == "036000291452")
}

@Test func aLookupFailureIsNotAnAnswerAboutTheCatalog() async throws {
    let catalog = FailingVariants()
    await #expect(throws: GlossedError.self) {
        try await BarcodeRung(catalog: catalog).resolve(scanned: seededGTIN)
    }
}

private struct FailingVariants: VariantLookup {
    func variant(gtin _: String) async throws(GlossedError) -> Variant? {
        throw GlossedError(.offline, userMessage: "no connection — try again in a sec.")
    }
}
