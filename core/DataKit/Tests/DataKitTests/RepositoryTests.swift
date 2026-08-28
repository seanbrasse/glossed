import Foundation
import Testing
@testable import DataKit

// Pure rules that repositories encode. Query behavior itself is proven by the
// pgTAP suite against real Postgres + RLS, which is the actual security
// boundary; these cover the Swift-side logic that pgTAP cannot see.

@Test func normalizationCollapsesPunctuationAndCase() {
    // Dedupe compares normalized names, so "Pro Filt'r" and "pro filtr" must agree.
    #expect(PersonalProductDraft.normalize("Pro Filt'r Soft Matte") == "pro filt r soft matte")
    #expect(PersonalProductDraft.normalize("  RARE   Beauty  ") == "rare beauty")
    #expect(PersonalProductDraft.normalize("niacinamide 10% + zinc") == "niacinamide 10 zinc")
}

@Test func fitAnswersMatchTheDatabaseEnum() {
    // A mismatch between these and fit_enum is a bug that only shows up at
    // write time, so it is asserted here instead.
    #expect(Fit.allCases.map(\.rawValue).sorted() == [
        "just_right", "too_dark", "too_light", "too_orange", "too_pink", "too_yellow"
    ])
    #expect(Fit.allCases.allSatisfy { $0.label == $0.label.lowercased() })
}
