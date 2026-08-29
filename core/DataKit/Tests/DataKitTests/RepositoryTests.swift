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
    #expect(draft.params().variant == nil)
}

@Test func theDraftCarriesTheVariantAsTyped() {
    // The create rung's third field (GLO-75). Sent verbatim — trimming and
    // empty-to-null are the server's rules, and duplicating them here is how
    // the two sides drift.
    let draft = PersonalProductDraft(
        brandID: UUID(), categoryID: UUID(), domain: .makeup,
        name: "soft pinch liquid blush", variant: "joy · 2.5ml mini"
    )
    #expect(draft.params().variant == "joy · 2.5ml mini")
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
     "brand_name":"rhode","category_id":"00000000-0000-0000-0000-0000000000d1",
     "category_slug":"cleanser","domain":"skincare",
     "scope":"canonical","n_face_offs":null,"variant_label":"150ml"}
    """#.utf8)
    let hit = try PostgrestClient.Configuration.jsonDecoder.decode(CatalogHit.self, from: raw)
    #expect(hit.faceOffCount == nil)
    #expect(hit.variantLabel == "150ml")
    // Pre-0016 rows carry no image fields at all; absent decodes as nil —
    // "no image", answered by the drawn mock, never a broken image.
    #expect(hit.catalogImageKey == nil)
    // 0017's ride-along (GLO-80): the id item_logged reports. Required on
    // purpose — a hit without one is a decode failure, not a silent nil that
    // an event would later have to invent an answer for.
    #expect(hit.categoryID == UUID(uuidString: "00000000-0000-0000-0000-0000000000d1"))
}

@Test func aHitCarriesItsCatalogImageWhenTheSearchNamesOne() throws {
    // 0016's ride-along (GLO-83): key + pixel size, so a row can reserve the
    // right width before the photo loads.
    let raw = Data(#"""
    {"id":"00000000-0000-0000-0000-0000000000b1","name":"pineapple refresh",
     "brand_name":"rhode","category_id":"00000000-0000-0000-0000-0000000000d1",
     "category_slug":"cleanser","domain":"skincare",
     "scope":"canonical","n_face_offs":null,"variant_label":"150ml",
     "catalog_image_key":"00000000-0000-0000-0000-0000000000c1/cut512.png",
     "catalog_image_width":512,"catalog_image_height":512}
    """#.utf8)
    let hit = try PostgrestClient.Configuration.jsonDecoder.decode(CatalogHit.self, from: raw)
    #expect(hit.catalogImageKey == "00000000-0000-0000-0000-0000000000c1/cut512.png")
    #expect(hit.catalogImageWidth == 512)
    #expect(hit.catalogImageHeight == 512)
}

@Test func aVariantDecodesItsStrength() throws {
    // GLO-56's stated gap, closed: `variant_label()` renders strength_pct
    // ("10% · 30ml") and the Swift side could not see the column at all.
    let raw = Data(#"""
    {"id":"00000000-0000-0000-0000-0000000000e1",
     "product_id":"00000000-0000-0000-0000-0000000000e2",
     "shade_code":null,"shade_hex":null,"size_ml":30,"strength_pct":10,
     "gtin":null,"height_mm":null,"price_cents":null}
    """#.utf8)
    let variant = try PostgrestClient.Configuration.jsonDecoder.decode(Variant.self, from: raw)
    #expect(variant.strengthPct == 10)
    #expect(variant.sizeML == 30)
}

@Test func itemStatusesMatchTheDatabaseEnum() {
    // `updateStatus` writes these raw values straight into `user_items.status`
    // (session-7 opening, GLO-72). A drift from `item_status` is a bug that
    // only shows up at write time, so it is asserted here — same treatment
    // as the fit enum below.
    #expect([ItemStatus.wantToTry, .own, .finished, .repurchased].map(\.rawValue) == [
        "want_to_try", "own", "finished", "repurchased"
    ])
}

@Test func aNearMatchIsAHitPlusItsReason() throws {
    // near_matches shares search_catalog's columns plus why (0018) — one
    // row shape, one decoder: the hit decodes from the same flat row.
    let raw = Data(#"""
    {"id":"00000000-0000-0000-0000-0000000000b1","name":"soft pinch liquid blush",
     "brand_name":"rare beauty","category_id":"10000000-0000-0000-0000-000000000001",
     "category_slug":"blush","domain":"makeup","scope":"canonical",
     "n_face_offs":null,"variant_label":null,
     "why":"similar name — check the shade and size"}
    """#.utf8)
    let match = try PostgrestClient.Configuration.jsonDecoder.decode(NearMatch.self, from: raw)
    #expect(match.hit.name == "soft pinch liquid blush")
    #expect(match.why == "similar name — check the shade and size")
    #expect(match.id == match.hit.id)
}

@Test func fitAnswersMatchTheDatabaseEnum() {
    // A mismatch between these and fit_enum is a bug that only shows up at
    // write time, so it is asserted here instead.
    #expect(Fit.allCases.map(\.rawValue).sorted() == [
        "just_right", "too_dark", "too_light", "too_orange", "too_pink", "too_yellow"
    ])
    #expect(Fit.allCases.allSatisfy { $0.label == $0.label.lowercased() })
}

@Test func aScanIsPaddedToTheCanonicalFourteen() {
    // The database's gtin14 column pads the stored side; this pads the scanned
    // side. One-sided normalization would make every scan miss (GLO-58).
    #expect(CatalogRepository.gtin14("810086012350") == "00810086012350")
    #expect(CatalogRepository.gtin14("0810086012350") == "00810086012350")
    #expect(CatalogRepository.gtin14("00810086012350") == "00810086012350")
}

@Test func aCodeThatIsNotAGTINIsNoCodeAtAll() {
    #expect(CatalogRepository.gtin14("not-a-code") == nil)
    #expect(CatalogRepository.gtin14("1234567") == nil) // seven digits: too short
    #expect(CatalogRepository.gtin14("123456781234567") == nil) // fifteen: too long
    #expect(CatalogRepository.gtin14("") == nil)
}
