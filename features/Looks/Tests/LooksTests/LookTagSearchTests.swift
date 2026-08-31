import Foundation
import Testing
@testable import Looks

// The tag picker's search (GLO-266). The scope is UNRULED — Sean: "your shelf
// (or maybe all of our items? Maybe the whole catalog but your shelf and
// categories first? Not sure)" — so what is asserted here is that the scope
// is a parameter, that each case behaves as its own name says, and that
// nothing about it is claim-shaped.

private let foundation = TagCategory(slug: "foundation", label: "foundation")

private func hit(_ label: String, mine: Bool) -> TagSearchResult {
    TagSearchResult(variantID: UUID(), label: label, category: foundation, isOnYourShelf: mine)
}

private func search(
    _ scope: LookTagSearchScope,
    _ answer: @escaping @Sendable (String) async throws -> [TagSearchResult]
) -> LookTagSearch {
    LookTagSearch(scope: scope, find: answer)
}

@Test func shelfFirstLiftsWhatYouOwnAndKeepsEachHalfsOwnOrder() {
    let results = [
        hit("catalog a", mine: false),
        hit("mine a", mine: true),
        hit("catalog b", mine: false),
        hit("mine b", mine: true)
    ]
    #expect(
        LookTagSearchScope.catalogShelfFirst.ranked(results).map(\.label)
            == ["mine a", "mine b", "catalog a", "catalog b"],
        "shelf first, and within each half the search's own relevance order survives"
    )
}

@Test func theOtherTwoScopesLeaveTheSearchsOrderExactlyAsItCame() {
    let results = [hit("catalog a", mine: false), hit("mine a", mine: true)]
    // Re-ranking the catalog's ranking would be this client second-guessing
    // the search, and it has no basis to.
    #expect(LookTagSearchScope.catalog.ranked(results).map(\.label) == ["catalog a", "mine a"])
    #expect(LookTagSearchScope.shelf.ranked(results).map(\.label) == ["catalog a", "mine a"])
}

@Test func onlyTheShelfFirstScopeSectionsAndEveryScopeSaysWhatItSearched() {
    #expect(LookTagSearchScope.catalogShelfFirst.isSectioned)
    #expect(!LookTagSearchScope.shelf.isSectioned)
    #expect(!LookTagSearchScope.catalog.isSectioned)
    for scope in LookTagSearchScope.allCases {
        #expect(!scope.line.isEmpty, "a search that excludes things must say what it covers")
        #expect(scope.line == scope.line.lowercased(), "lowercase copy")
    }
}

@MainActor
@Test func aShortQuerySearchesNothingAndSaysWhy() async {
    let model = LookTagSearchModel(search(.catalog) { _ in
        Issue.record("a one-letter query must not reach the catalog")
        return []
    })
    model.query = "f"
    await model.task?.value
    #expect(model.results.isEmpty)
    #expect(model.vacancy == .tooShort)
}

@MainActor
@Test func aQueryThatMatchesNothingIsAVacancyNotASilentEmptyList() async {
    let model = LookTagSearchModel(search(.catalogShelfFirst) { _ in [] })
    model.query = "zzzz"
    await model.task?.value
    #expect(model.vacancy == .nothingFound)
    #expect(model.sections.isEmpty, "no eyebrow stands over nothing")
}

@MainActor
@Test func resultsArriveRankedByTheScopeAndSplitIntoItsTwoSections() async {
    let model = LookTagSearchModel(search(.catalogShelfFirst) { _ in
        [hit("catalog one", mine: false), hit("mine one", mine: true)]
    })
    model.query = "fenty"
    await model.task?.value

    #expect(model.results.map(\.label) == ["mine one", "catalog one"])
    #expect(model.sections.count == 2)
    #expect(model.sections[0].isShelf)
    #expect(model.sections[0].results.map(\.label) == ["mine one"])
    #expect(model.sections[1].results.map(\.label) == ["catalog one"])
}

@MainActor
@Test func anUnsectionedScopeOffersOneUnlabelledSection() async {
    let model = LookTagSearchModel(search(.shelf) { _ in
        [hit("mine one", mine: true), hit("mine two", mine: true)]
    })
    model.query = "rare"
    await model.task?.value

    #expect(model.sections.count == 1)
    #expect(!model.sections[0].isShelf, "nothing to contrast with, so nothing is labelled")
}

@MainActor
@Test func aFailedSearchNamesItselfAndClearsOnTheNextQuery() async {
    struct Offline: Error {}
    let flaky = FlakySearch()
    let model = LookTagSearchModel(search(.catalog) { query in try await flaky.answer(query) })

    model.query = "fenty"
    await model.task?.value
    #expect(model.failure != nil)
    #expect(model.results.isEmpty)

    model.query = "fenty pro"
    await model.task?.value
    #expect(model.failure == nil, "the way onward is live")
    #expect(model.results.count == 1)
}

@MainActor
@Test func aResultBecomesTheProductTheTagHoldsWithoutReassemblingItsLabel() {
    // The composer must not invent a shade name: whatever the catalog
    // rendered is what the tag carries.
    let result = TagSearchResult(
        variantID: UUID(),
        label: "fenty pro filt'r · 330",
        category: foundation,
        isOnYourShelf: true
    )
    let tagged = result.tagged
    #expect(tagged.variantID == result.variantID)
    #expect(tagged.label == "fenty pro filt'r · 330")
    #expect(tagged.category == foundation)
}

/// Fails once, then answers — the composer's own retry shape.
private actor FlakySearch {
    private var failed = false

    func answer(_ query: String) async throws -> [TagSearchResult] {
        struct Offline: Error {}
        guard failed else {
            failed = true
            throw Offline()
        }
        return [hit(query, mine: false)]
    }
}
