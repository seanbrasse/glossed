import Foundation
import Supabase
import Testing
@testable import DataKit

// The discover wire types (0040/0035). Decoded with the same configuration
// the live client uses, because that is the only decode that matters.

@Test func aDiscoverHitIsAHitPlusItsBasis() throws {
    // discover_for_user shares search_catalog's columns plus (basis,
    // basis_n) — one row shape, one decoder, the NearMatch treatment.
    let raw = Data(#"""
    {"id":"00000000-0000-0000-0000-0000000000d1","name":"niacinamide 10% + zinc",
     "brand_name":"the ordinary","category_id":"10000000-0000-0000-0000-000000000004",
     "category_slug":"serum","domain":"skincare","scope":"canonical",
     "n_face_offs":null,"variant_label":null,"catalog_image_key":null,
     "catalog_image_width":null,"catalog_image_height":null,
     "basis":"taste","basis_n":3}
    """#.utf8)
    let row = try PostgrestClient.Configuration.jsonDecoder.decode(DiscoverHit.self, from: raw)
    #expect(row.hit.name == "niacinamide 10% + zinc")
    #expect(row.basis == .taste)
    #expect(row.basisN == 3)
    #expect(row.id == row.hit.id)
}

@Test func basisKeysMatchTheRPCVocabulary() {
    // 0040 emits these exact strings. Exhaustive on purpose: a new basis
    // added server-side must be a compile-visible decision here, not a row
    // silently rendered under the wrong words.
    #expect([DiscoverHit.Basis.taste, .shade, .everyone, .popular, .exploration].map(\.rawValue) == [
        "taste", "shade", "everyone", "popular", "exploration"
    ])
}

@Test func aCrosswalkHitCarriesItsAnchorAndItsN() throws {
    let raw = Data(#"""
    {"anchor_variant_id":"00000000-0000-0000-0000-0000000000a1",
     "anchor_label":"fenty beauty 240 · 32ml",
     "id":"00000000-0000-0000-0000-0000000000d2","name":"soft pinch liquid blush",
     "brand_name":"rare beauty","category_id":"10000000-0000-0000-0000-000000000001",
     "category_slug":"blush","domain":"makeup","scope":"canonical",
     "n_face_offs":6,"variant_label":"joy · 7.5ml","catalog_image_key":null,
     "catalog_image_width":null,"catalog_image_height":null,"n":8}
    """#.utf8)
    let row = try PostgrestClient.Configuration.jsonDecoder.decode(CrosswalkHit.self, from: raw)
    #expect(row.anchorLabel == "fenty beauty 240 · 32ml")
    #expect(row.n == 8)
    #expect(row.hit.faceOffCount == 6)
}

@Test func anAffinityRowIsAReceiptWithItsConfidence() throws {
    // 0035's output shape: the receipt's n is the caller's own signal
    // count, and w doubles as the ConfidenceMeter value.
    let raw = Data(#"""
    {"attribute_chip_id":"00000000-0000-0000-0000-0000000000f1",
     "label":"fragrance-free","raw_score":1.75,"n_signals":3,
     "w":0.2307692307692308,"shrunk_score":0.4038461538461538}
    """#.utf8)
    let row = try PostgrestClient.Configuration.jsonDecoder.decode(AffinityRow.self, from: raw)
    #expect(row.label == "fragrance-free")
    #expect(row.nSignals == 3)
    #expect(abs(row.w - 3.0 / 13.0) < 0.0001)
    #expect(row.id == row.attributeChipID)
}
