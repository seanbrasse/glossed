import Foundation
import Supabase
import Testing
@testable import DataKit

// Pure rules that repositories encode. Query behavior itself is proven by the
// pgTAP suite against real Postgres + RLS, which is the actual security
// boundary; these cover the Swift-side logic that pgTAP cannot see.

@Test func theDraftCarriesTheScannedCodeRatherThanDroppingIt() {
    // A create that follows a barcode miss has the strongest identifier the
    // user will ever hand us in its pocket. Late-binding promotion reads it.
    let draft = PersonalProductDraft(
        brandID: UUID(), categoryID: UUID(), domain: .haircare,
        name: "Kinky-Curly Knot Today", scannedGTIN: "0850000000004"
    )
    #expect(draft.params().gtin == "0850000000004")
    #expect(draft.params().name == "Kinky-Curly Knot Today")
    // No `normalized_name` is sent: the database owns that rule now. This test
    // used to assert `pro filt r soft matte` under a comment claiming
    // "Pro Filt'r" and "pro filtr" must agree — the assertion and its own
    // comment disagreed, and the seed sided with the comment.
}

@Test func aDraftWithoutAScanSendsNoCode() {
    let draft = PersonalProductDraft(
        brandID: UUID(), categoryID: UUID(), domain: .makeup, name: "hand cream"
    )
    #expect(draft.params().gtin == nil)
}

@Test func theSearchFloorHasOneDefinition() {
    // The rung enforces this before recording a failed search. Drift here alone
    // writes false demand into the fill queue (GLO-55).
    #expect(CatalogRepository.minimumQueryLength == 2)
}

@Test func aHitWithNoAggregateRowClaimsNothing() throws {
    // Not zero. A shopper reads "0 face-offs" as "nobody has tried this", and
    // an absent aggregate row is not that claim (GLO-63).
    let raw = Data(#"""
    {"id":"00000000-0000-0000-0000-0000000000b1","name":"pineapple refresh",
     "brand_name":"rhode","category_slug":"cleanser","domain":"skincare",
     "scope":"canonical","n_face_offs":null,"variant_label":"150ml"}
    """#.utf8)
    let hit = try PostgrestClient.Configuration.jsonDecoder.decode(CatalogHit.self, from: raw)
    #expect(hit.faceOffCount == nil)
    #expect(hit.variantLabel == "150ml")
}

@Test func fitAnswersMatchTheDatabaseEnum() {
    // A mismatch between these and fit_enum is a bug that only shows up at
    // write time, so it is asserted here instead.
    #expect(Fit.allCases.map(\.rawValue).sorted() == [
        "just_right", "too_dark", "too_light", "too_orange", "too_pink", "too_yellow"
    ])
    #expect(Fit.allCases.allSatisfy { $0.label == $0.label.lowercased() })
}
