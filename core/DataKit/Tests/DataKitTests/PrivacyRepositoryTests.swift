import Foundation
import Testing
@testable import DataKit

// Pure rules PrivacyRepository encodes. The queries themselves — RLS, the
// minor lock, can_view's evaluation order — are proven by the pgTAP suite
// against real Postgres, which is the actual security boundary. These cover
// the Swift-side decisions pgTAP cannot see.

@Test func theLabelIsOnlyYouNotJustYou() {
    // Sean's rename, Aug 29. The design kit's privacy frame still shows the old
    // string and is superseded, not a specification.
    #expect(PrivacyScope.onlyYou.label == "only you")
    #expect(!PrivacyScope.allCases.contains { $0.label.contains("just") })
}

@Test func everyScopeLabelIsLowercase() {
    // Lowercase UI copy is a house rule, and these strings go straight onto
    // the screen.
    for scope in PrivacyScope.allCases {
        #expect(scope.label == scope.label.lowercased())
        #expect(scope.explanation == scope.explanation.lowercased())
    }
}

@Test func friendsMeansMutualFollow() {
    // Sean, Aug 29. The permissive reading would let a stranger self-serve into
    // a friends-scoped shelf by tapping follow, which makes `friends` a slower
    // spelling of `public`. The copy has to say so.
    #expect(PrivacyScope.friends.explanation.contains("follow you back"))
}

@Test func theWireValuesMatchTheDatabaseEnum() {
    // A mismatch here is a silent write of a value scope_enum will reject.
    // `public` is a Swift keyword, so the case name and the wire value differ
    // in exactly one place and this is it.
    #expect(PrivacyScope.onlyYou.rawValue == "only_you")
    #expect(PrivacyScope.friends.rawValue == "friends")
    #expect(PrivacyScope.publicScope.rawValue == "public")
    #expect(Set(VisibilitySurface.allCases.map(\.rawValue))
        == ["shelf", "rankings", "routines", "looks"])
}

@Test func aUserWithNoRowIsPrivateNotUnknown() {
    // No row is not a missing answer — it is `only_you`, the same rule
    // can_view applies server-side. The defaulted value has to agree, or a
    // screen renders "unknown" for a state that is definitively private.
    let defaults = PrivacyScopes()
    for surface in VisibilitySurface.allCases {
        #expect(defaults.scope(for: surface) == .onlyYou)
    }
    #expect(defaults.discoverable == false)
}

@Test func discoverableDefaultsOffAndIsNotAScope() {
    // Being visible and wanting to be surfaced are different questions (§1.3).
    // A public shelf reachable by link is not consent to appear in a stranger's
    // suggestions, so this ships off and moves only by its own control.
    #expect(PrivacyScopes(shelf: .publicScope).discoverable == false)
}

@Test func theSummaryIsDerivedAndSaysMixedRatherThanRounding() {
    // The summary above the four rows is READ-ONLY and derived. A stored one
    // could disagree with the rows, and the rows are the truth.
    #expect(PrivacyScopes().overallScope == .onlyYou)

    let allPublic = PrivacyScopes(
        shelf: .publicScope, rankings: .publicScope,
        routines: .publicScope, looks: .publicScope
    )
    #expect(allPublic.overallScope == .publicScope)

    // One row differing makes it mixed — NOT rounded to the loosest, which
    // would show "public" to someone whose rankings are private, and not to
    // the tightest, which would hide that something is public.
    let mixed = PrivacyScopes(
        shelf: .publicScope, rankings: .friends,
        routines: .publicScope, looks: .publicScope
    )
    #expect(mixed.overallScope == nil)
}

@Test func aSingleFriendsRowIsMixedNotFriends() {
    // The subtle case: three private and one friends is still mixed. Reporting
    // "friends" would overstate exposure; reporting "only you" would understate
    // it. Neither is safe, so the screen says mixed.
    let one = PrivacyScopes(rankings: .friends)
    #expect(one.overallScope == nil)
}

@Test func scopeLookupCoversEverySurface() {
    // A surface added to the enum without a case here would silently read the
    // wrong row. Distinct values per surface make that visible.
    let scopes = PrivacyScopes(
        shelf: .publicScope, rankings: .friends,
        routines: .onlyYou, looks: .publicScope
    )
    #expect(scopes.scope(for: .shelf) == .publicScope)
    #expect(scopes.scope(for: .rankings) == .friends)
    #expect(scopes.scope(for: .routines) == .onlyYou)
    #expect(scopes.scope(for: .looks) == .publicScope)
}

@Test func scopesDecodeFromTheWireShape() throws {
    // The column names are the coding keys; a rename on either side breaks
    // here rather than at runtime on someone's privacy screen.
    let json = Data("""
    {"shelf":"public","rankings":"friends","routines":"only_you","looks":"only_you","discoverable":true}
    """.utf8)
    let decoded = try JSONDecoder().decode(PrivacyScopes.self, from: json)
    #expect(decoded.shelf == .publicScope)
    #expect(decoded.rankings == .friends)
    #expect(decoded.routines == .onlyYou)
    #expect(decoded.discoverable)
    #expect(decoded.overallScope == nil)
}
