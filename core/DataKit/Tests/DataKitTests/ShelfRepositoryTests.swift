import Foundation
import Testing
@testable import DataKit

// Pure rules the shelf repository encodes. Query behavior itself is proven by the
// pgTAP suite against real Postgres + RLS, which is the actual security
// boundary; these cover the Swift-side logic that pgTAP cannot see.

@Test func weekOneIsTheFirstSevenDays() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let day = 86400.0
    #expect(ShelfRepository.week(startedOn: start, loggedOn: start) == 1)
    #expect(ShelfRepository.week(startedOn: start, loggedOn: start + 6 * day) == 1)
    #expect(ShelfRepository.week(startedOn: start, loggedOn: start + 7 * day) == 2)
    #expect(ShelfRepository.week(startedOn: start, loggedOn: start + 69 * day) == 10)
}

@Test func weekIsNilWithoutAStartDate() {
    // Makeup and fragrance have nothing to wear in, so their chips carry no week.
    #expect(ShelfRepository.week(startedOn: nil, loggedOn: Date()) == nil)
}

@Test func weekIgnoresLogsBeforeTheStartDate() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(ShelfRepository.week(startedOn: start, loggedOn: start - 86400) == nil)
}

@Test func logDraftGeneratesADistinctIdempotencyKeyPerDraft() {
    let variant = UUID()
    #expect(LogDraft(variantID: variant).clientID != LogDraft(variantID: variant).clientID)
    // …but a caller-supplied key is preserved, so a retry resolves to one row.
    let fixed = UUID()
    #expect(LogDraft(variantID: variant, clientID: fixed).clientID == fixed)
}
