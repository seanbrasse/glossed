import Foundation
import Testing
@testable import Stylist

private let sample = """
{"text":"here's the morning, with the one gap named.",
 "blocks":[
   {"type":"routine_draft","title":"glass skin, morning","slot":"am","targets":["dryness"],
    "steps":[{"user_item_id":"11111111-1111-4111-8111-111111111111","product_name":"pineapple refresh",
              "brand_name":"rhode","category_label":"cleanser","note":null}],
    "gap":{"category_label":"sunscreen","reason":"nothing on the shelf"}},
   {"type":"product_list","reason":"two serums","products":[
     {"product_id":"22222222-2222-4222-8222-222222222222","name":"niacinamide 10% + zinc",
      "brand_name":"the ordinary","category_slug":"serum","on_shelf":true,"rank_position":1,
      "ranked_in_category":2,"n_face_offs":null,"catalog_image_key":null},
     {"product_id":"55555555-5555-4555-8555-555555555555","name":"cloud serum",
      "brand_name":"somebrand","category_slug":"serum","on_shelf":false,"rank_position":null,
      "ranked_in_category":null,"n_face_offs":12,"catalog_image_key":null,
      "basis_label":"face-offs by people who wear your shade","basis_n":12}]},
   {"type":"look_ref","look_id":"33333333-3333-4333-8333-333333333333","caption":"golden hour","photo_n":2},
   {"type":"collection_ref","collection_id":"44444444-4444-4444-8444-444444444444",
    "title":"holy grails only","item_n":1},
   {"type":"person_card","handle":"someone"}
 ],
 "chips":["build my pm routine","show the 3"],
 "grounded_in":["profile","shelf","search_catalog"],
 "tools_used":["propose_routine","search_catalog","suggest_chips"]}
"""

@Test func aReplyDecodesEveryBlockItKnowsAndSkipsTheOnesItDoesNot() throws {
    let reply = try StylistReply.decode(Data(sample.utf8))
    #expect(reply.text.hasPrefix("here's the morning"))
    #expect(reply.blocks.count == 4, "person_card is a future block — skipped, not fatal")
    guard case let .routine(draft) = reply.blocks[0] else { Issue.record("first block is the routine"); return }
    #expect(draft.steps.first?.brandName == "rhode")
    #expect(draft.gap?.categoryLabel == "sunscreen")
    guard case let .products(list) = reply.blocks[1] else { Issue.record("second block is the list"); return }
    #expect(list.products.first?.onShelf == true)
    #expect(list.products.first?.rankPosition == 1)
    #expect(list.products.first?.basisLabel == nil, "a row without a basis decodes — the key is optional")
    #expect(list.products.last?.basisLabel == "face-offs by people who wear your shade")
    #expect(list.products.last?.basisN == 12)
    guard case let .look(look) = reply.blocks[2] else { Issue.record("third block is the look"); return }
    #expect(look.photoN == 2)
    guard case let .collection(collection) = reply.blocks[3]
    else { Issue.record("fourth block is the collection"); return }
    #expect(collection.itemN == 1)
    #expect(reply.chips == ["build my pm routine", "show the 3"])
    #expect(reply.groundedIn.contains("search_catalog"))
}

@Test func aBareReplyStillDecodes() throws {
    let reply = try StylistReply.decode(Data(#"{"text":"that one's outside what I do."}"#.utf8))
    #expect(reply.blocks.isEmpty)
    #expect(reply.chips.isEmpty)
}

@Test func theRequestIsTextOnlyAndSnakeCased() throws {
    let data = try JSONEncoder().encode(StylistTurnRequest(messages: [
        StylistTranscriptTurn(role: .user, text: "hi"),
        StylistTranscriptTurn(role: .assistant, text: "hello")
    ]))
    let json = String(bytes: data, encoding: .utf8) ?? ""
    #expect(json.contains(#""role":"assistant""#))
    #expect(!json.contains("blocks"))
}
