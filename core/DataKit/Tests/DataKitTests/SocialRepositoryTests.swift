import Foundation
import Testing
@testable import DataKit

// The wire shapes and the rules the Swift side encodes. Visibility itself —
// who public_profile returns nothing for, which exclusions suggested_people
// applies — is proven by pgTAP against real Postgres and RLS.

@Test func aPublicProfileDecodesEveryColumnTheRPCReturns() throws {
    // A rename on either side breaks here rather than at runtime on someone's
    // profile screen, where a missing count silently renders as a blank claim.
    let json = Data("""
    {"handle":"maya_k","display_name":"maya","avatar_seed":"seed-1","bio":"i like blush",
     "badge_skin_type":"combo","badge_anchor":"fenty beauty 220","badge_hair_pattern":null,
     "followers":12,"following":30,"shelf_n":8,"ranked_lists_n":3,
     "shelf_visible":true,"rankings_visible":false,"routines_visible":false}
    """.utf8)
    let profile = try JSONDecoder().decode(PublicProfile.self, from: json)
    #expect(profile.handle == "maya_k")
    #expect(profile.badgeAnchor == "fenty beauty 220")
    #expect(profile.followers == 12)
    #expect(profile.shelfN == 8)
    #expect(profile.rankedListsN == 3)
    #expect(profile.shelfVisible)
    #expect(!profile.rankingsVisible)
}

@Test func anUnpublishedBadgeIsNilRatherThanAbsent() throws {
    // A badge the owner did not opt into comes back null. Nil means NOT
    // PUBLISHED, never "not known" — the RPC does not distinguish those for
    // the caller, and a screen must not invent the distinction.
    let json = Data("""
    {"handle":"juli_r","display_name":null,"avatar_seed":null,"bio":null,
     "badge_skin_type":null,"badge_anchor":null,"badge_hair_pattern":null,
     "followers":0,"following":0,"shelf_n":0,"ranked_lists_n":0,
     "shelf_visible":false,"rankings_visible":false,"routines_visible":false}
    """.utf8)
    let profile = try JSONDecoder().decode(PublicProfile.self, from: json)
    #expect(profile.badgeSkinType == nil)
    #expect(profile.badgeAnchor == nil)
    #expect(profile.badgeHairPattern == nil)
    // And every count is still present. A profile with nothing published still
    // carries its n — zero is a number, and the claim it backs is "0 things".
    #expect(profile.shelfN == 0)
    #expect(profile.followers == 0)
}

@Test func everyCountIsNonOptional() throws {
    // Deliberate: an optional count invites `?? 0` at the call site, which
    // renders a real zero and a missing value identically. The RPC always
    // returns a number, so the type says so.
    let json = Data("""
    {"handle":"h","display_name":null,"avatar_seed":null,"bio":null,
     "badge_skin_type":null,"badge_anchor":null,"badge_hair_pattern":null,
     "followers":1,"following":2,"shelf_n":3,"ranked_lists_n":4,
     "shelf_visible":true,"rankings_visible":true,"routines_visible":true}
    """.utf8)
    let profile = try JSONDecoder().decode(PublicProfile.self, from: json)
    #expect(profile.followers + profile.following + profile.shelfN + profile.rankedListsN == 10)
}

@Test func aSuggestionCarriesANamedReasonAndItsN() throws {
    let json = Data("""
    [{"user_id":"11111111-1111-4111-8111-111111111111","handle":"juli_r",
      "display_name":"juli","reason":"wears fenty beauty 220","reason_kind":"anchor","n":14}]
    """.utf8)
    let people = try JSONDecoder().decode([SuggestedPerson].self, from: json)
    let person = try #require(people.first)
    #expect(person.reason == "wears fenty beauty 220")
    #expect(person.reasonKind == "anchor")
    #expect(person.n == 14)
    #expect(person.id == person.userID)
}

@Test func theSkinReasonNeverStatesTheValue() throws {
    // Sean's ruling, Aug 29: consent AND non-disclosure. The badge gate is why
    // the row exists; this is why the sentence does not quote a profile back
    // at a stranger. Pinned here as well as in pgTAP because this string is
    // what actually lands on the card.
    let json = Data("""
    [{"user_id":"22222222-2222-4222-8222-222222222222","handle":"x",
      "display_name":null,"reason":"similar skin to yours","reason_kind":"skin_type","n":0}]
    """.utf8)
    let person = try #require(try JSONDecoder().decode([SuggestedPerson].self, from: json).first)
    #expect(person.reason == "similar skin to yours")
    for value in ["combo", "oily", "dry", "normal", "sensitive"] {
        #expect(!person.reason.contains(value))
    }
}

@Test func aReasonIsNeverEmpty() throws {
    // The RPC returns no row rather than a reasonless one, so there is no
    // blank-card state to handle. If this ever decodes an empty reason, the
    // guarantee has moved and the views built on it are wrong.
    let json = Data("""
    [{"user_id":"33333333-3333-4333-8333-333333333333","handle":"y",
      "display_name":null,"reason":"wears rare beauty 1 fair neutral","reason_kind":"anchor","n":2}]
    """.utf8)
    let people = try JSONDecoder().decode([SuggestedPerson].self, from: json)
    #expect(people.allSatisfy { !$0.reason.isEmpty })
}

@Test func anEmptySuggestionListDecodesRatherThanFailing() throws {
    // Empty is the CORRECT state until people opt into badges, not an error
    // and not a loading failure. A decoder that choked here would turn the
    // expected case into a crash on first launch.
    let people = try JSONDecoder().decode([SuggestedPerson].self, from: Data("[]".utf8))
    #expect(people.isEmpty)
}
