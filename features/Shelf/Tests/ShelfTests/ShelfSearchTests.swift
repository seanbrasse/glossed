import DataKit
import DesignSystem
import Foundation
import Testing
@testable import Shelf

// MARK: - Helpers

private func shelfItem(
    brand: String,
    name: String,
    category: String = "blush",
    variant: String? = nil,
    domain: Domain = .makeup
) -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: brand,
        name: name,
        categorySlug: category,
        categoryLabel: category,
        domain: domain,
        variant: variant,
        packaging: .dropper
    )
}

@MainActor
private func model(_ sections: [ShelfSection], domains: Set<Domain> = [.makeup, .skincare]) -> ShelfModel {
    ShelfModel(sections: sections, selectedDomains: domains)
}

@MainActor
struct ShelfSearchTests {
    private let blushes = ShelfSection(slug: "blush", label: "blush", domain: .makeup, items: [
        shelfItem(brand: "rare beauty", name: "soft pinch liquid blush", variant: "joy · 7.5ml"),
        shelfItem(brand: "rhode", name: "pocket blush", variant: "freckle")
    ])
    private let cleansers = ShelfSection(slug: "cleanser", label: "cleanser", domain: .skincare, items: [
        shelfItem(brand: "cerave", name: "hydrating facial wash", category: "cleanser", domain: .skincare)
    ])

    @Test func anEmptyQueryFiltersNothing() {
        let live = model([blushes, cleansers])
        live.searchQuery = "   "
        #expect(live.shownItemCount == 3)
        #expect(!live.searchCameUpEmpty)
    }

    @Test func matchesReachBrandNameAndVariant() {
        let live = model([blushes, cleansers])

        live.searchQuery = "rhode"
        #expect(live.shownSections.flatMap(\.items).map(\.name) == ["pocket blush"])

        live.searchQuery = "soft pinch"
        #expect(live.shownItemCount == 1)

        // The variant is a fact the owner remembers — "the joy one".
        live.searchQuery = "joy"
        #expect(live.shownSections.flatMap(\.items).map(\.brand) == ["rare beauty"])
    }

    @Test func theBayLabelAnswersBecauseCategoryWordsAreHowPeopleAsk() {
        // The ticket's own motivating query: "where's my cleanser" — the
        // product is named "hydrating facial wash", so only the bay label can
        // answer it.
        let live = model([blushes, cleansers])
        live.searchQuery = "cleanser"
        #expect(live.shownSections.map(\.slug) == ["cleanser"])
    }

    @Test func aBayWithNoMatchesDropsOutWhole() {
        let live = model([blushes, cleansers])
        live.searchQuery = "rare"
        // The cleanser bay has no match — rendering it empty would read as an
        // empty shelf, so it leaves entirely.
        #expect(live.shownSections.map(\.slug) == ["blush"])
    }

    @Test func searchRespectsTheDomainFilter() {
        let live = model([blushes, cleansers], domains: [.skincare])
        // "blush" matches two makeup items, but makeup is off — search narrows
        // the shelf you are looking at, it does not widen it.
        live.searchQuery = "blush"
        #expect(live.shownItemCount == 0)
        #expect(live.searchCameUpEmpty)
    }

    @Test func caseAndAccentsDoNotHideAnItem() {
        let sections = [ShelfSection(slug: "fragrance", label: "fragrance", domain: .fragrance, items: [
            shelfItem(brand: "Chloé", name: "Eau de Parfum", category: "fragrance", domain: .fragrance)
        ])]
        let live = model(sections, domains: [.fragrance])
        live.searchQuery = "chloe"
        #expect(live.shownItemCount == 1)
    }

    @Test func emptyHandedIsAVerdictOnlyWhenAQueryWasAsked() {
        let live = model([blushes, cleansers])
        live.searchQuery = "shampoo that does not exist"
        #expect(live.searchCameUpEmpty)

        live.searchQuery = ""
        #expect(!live.searchCameUpEmpty)
        #expect(live.shownItemCount == 3)
    }
}
