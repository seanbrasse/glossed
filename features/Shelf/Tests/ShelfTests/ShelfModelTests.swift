import DataKit
import DesignSystem
import Foundation
import Testing
@testable import Shelf

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

private func item(
    _ name: String,
    brand: String = "rare beauty",
    rank: Int? = nil,
    daysAgo: Double? = nil
) -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: brand,
        name: name,
        categorySlug: "blush",
        categoryLabel: "blush",
        domain: .makeup,
        packaging: .dropper,
        rank: rank,
        loggedAt: daysAgo.map { epoch.addingTimeInterval(-$0 * 86400) }
    )
}

private func section(_ slug: String, domain: Domain, items: [ShelfItem] = [item("x")]) -> ShelfSection {
    ShelfSection(slug: slug, label: slug, domain: domain, items: items)
}

@MainActor
private func model(
    _ sections: [ShelfSection],
    domains: Set<Domain> = Set(ShelfModel.domains),
    sort: ShelfSort = .favorite,
    viewMode: ShelfViewMode = .shelf
) -> ShelfModel {
    ShelfModel(sections: sections, selectedDomains: domains, sort: sort, viewMode: viewMode)
}

// MARK: - The domain filter

@MainActor
@Test func onlyTheSelectedDomainsGetBays() {
    let live = model(
        [section("blush", domain: .makeup), section("cleanser", domain: .skincare)],
        domains: [.makeup]
    )
    #expect(live.bays.map(\.label) == ["blush"])
}

@MainActor
@Test func theCountFollowsTheFilterRatherThanTheShelf() {
    // A count that ignored the filter would contradict the bays under it.
    let live = model(
        [
            section("blush", domain: .makeup, items: [item("a"), item("b")]),
            section("cleanser", domain: .skincare, items: [item("c")])
        ],
        domains: [.makeup]
    )
    #expect(live.shownItemCount == 2)
    live.toggle(.skincare)
    #expect(live.shownItemCount == 3)
}

@MainActor
@Test func turningEveryDomainOffLeavesAShelfWithNoBaysAndNoCrash() {
    let live = model([section("blush", domain: .makeup)], domains: [])
    #expect(live.bays.isEmpty)
    #expect(live.shownItemCount == 0)
}

@MainActor
@Test func theFragranceNoteAppearsOnlyWhileFragranceIsOn() {
    let live = model([section("scent", domain: .fragrance)], domains: [.makeup])
    #expect(live.showsFragranceNote == false)
    live.toggle(.fragrance)
    #expect(live.showsFragranceNote)
}

@MainActor
@Test func theDomainOrderIsTheKitsRatherThanTheEnumsDeclarationOrder() {
    // `Domain.allCases` order is a schema detail; this one is a design choice
    // and the filter reads left to right.
    #expect(ShelfModel.domains.map(\.rawValue) == ["makeup", "skincare", "haircare", "fragrance"])
    #expect(Set(ShelfModel.domains) == Set(Domain.allCases))
}

// MARK: - Ordering

@Test func favouriteOrdersByRankAndParksTheUnrankedAtTheEnd() {
    // Unranked ahead of ranked would read as "these are your favourites",
    // which is the one thing this sort must not say about them.
    let ordered = ShelfModel.ordered(
        [item("c", rank: 3), item("unranked"), item("a", rank: 1), item("b", rank: 2)],
        by: .favorite
    )
    #expect(ordered.map(\.name) == ["a", "b", "c", "unranked"])
}

@Test func recentPutsTheNewestFirstAndTheUndatedLast() {
    // A missing date guessed as "now" would park an item at the top of the
    // shelf as though it had just been logged.
    let ordered = ShelfModel.ordered(
        [item("old", daysAgo: 30), item("undated"), item("new", daysAgo: 1)],
        by: .recent
    )
    #expect(ordered.map(\.name) == ["new", "old", "undated"])
}

@Test func brandOrdersAlphabeticallyIgnoringCase() {
    let ordered = ShelfModel.ordered(
        [item("x", brand: "rhode"), item("y", brand: "Glossier"), item("z", brand: "byoma")],
        by: .brand
    )
    #expect(ordered.map(\.brand) == ["byoma", "Glossier", "rhode"])
}

@Test func everySortIsStableWhenTheKeysTie() {
    // SwiftUI re-sorts on every redraw. A comparator that leaves ties
    // undecided makes the shelf shuffle itself while someone is looking at it,
    // which reads as a bug and hides the ordering the sort is meant to show.
    for sort in ShelfSort.allCases {
        let tied = [item("c"), item("a"), item("b")]
        let once = ShelfModel.ordered(tied, by: sort).map(\.name)
        let twice = ShelfModel.ordered(ShelfModel.ordered(tied, by: sort), by: sort).map(\.name)
        #expect(once == ["a", "b", "c"])
        #expect(once == twice)
    }
}

@MainActor
@Test func changingTheSortReordersTheBaysAndNotJustAListSomewhere() {
    // The fixture is built so the three sorts disagree — a shelf that ordered
    // its bays once and then ignored the pills would pass a weaker version of
    // this test without doing anything.
    let live = model(
        [section("blush", domain: .makeup, items: [
            item("ranked-second", brand: "alpha", rank: 2, daysAgo: 1),
            item("ranked-first", brand: "zed", rank: 1, daysAgo: 30)
        ])],
        domains: [.makeup]
    )
    #expect(live.bays[0].items.map(\.name) == ["ranked-first", "ranked-second"])
    live.sort = .brand
    #expect(live.bays[0].items.map(\.name) == ["ranked-second", "ranked-first"])
    live.sort = .recent
    #expect(live.bays[0].items.map(\.name) == ["ranked-second", "ranked-first"])
}

// MARK: - Shelf or list

@MainActor
@Test func bothViewsRenderTheSameItemsInTheSameOrder() {
    // The toggle changes what you can do with the shelf, not what is true
    // about it. Two views that disagreed about the order would make the sort
    // pills mean different things depending on which was showing.
    let live = model(
        [section("blush", domain: .makeup, items: [
            item("second", brand: "alpha", rank: 2),
            item("first", brand: "zed", rank: 1)
        ])],
        domains: [.makeup]
    )
    for sort in ShelfSort.allCases {
        live.sort = sort
        let inBays = live.bays.flatMap(\.items).map(\.id)
        let inSections = live.shownSections.flatMap(\.items).map(\.id)
        #expect(inBays == inSections)
    }
}

@MainActor
@Test func onlyOneCategoryIsOpenAtATime() {
    let live = model([section("blush", domain: .makeup), section("cleanser", domain: .skincare)])
    live.toggleSection("blush")
    #expect(live.openSection == "blush")
    live.toggleSection("cleanser")
    #expect(live.openSection == "cleanser")
}

@MainActor
@Test func tappingTheOpenCategoryClosesIt() {
    // Without this an accordion can only ever be opened, and the count on a
    // closed card — the reason to collapse one at all — becomes unreachable.
    let live = model([section("blush", domain: .makeup)], domains: [.makeup])
    live.toggleSection("blush")
    live.toggleSection("blush")
    #expect(live.openSection == nil)
}

@MainActor
@Test func theViewModeSurvivesAFilterChange() {
    // Switching domains is not a reason to be thrown back to the other view.
    let live = model([section("blush", domain: .makeup)], viewMode: .list)
    live.toggle(.haircare)
    #expect(live.viewMode == .list)
}

// MARK: - The item sheet

@MainActor
@Test func theRankDenominatorCountsOnlyWhatHasBeenRanked() {
    // "#1 of 5" when three of the five have never been compared claims a
    // comparison nobody made. That is the star rating this product does not
    // have, spelled differently.
    let ranked = [item("a", rank: 1), item("b", rank: 2)]
    let unranked = [item("c"), item("d"), item("e")]
    let live = model([section("blush", domain: .makeup, items: ranked + unranked)])
    #expect(live.rankedCount(inCategoryOf: ranked[0]) == 2)
}

@MainActor
@Test func theDenominatorIgnoresTheDomainFilter() {
    // Turning off a domain does not change where a product placed, and a sheet
    // opened from a filtered shelf must not renumber it.
    let items = [item("a", rank: 1), item("b", rank: 2)]
    let live = model([section("blush", domain: .makeup, items: items)], domains: [])
    #expect(live.bays.isEmpty)
    #expect(live.rankedCount(inCategoryOf: items[0]) == 2)
}

@MainActor
@Test func anItemInNoKnownCategoryGetsNoDenominatorRatherThanAWrongOne() {
    let live = model([section("blush", domain: .makeup, items: [item("a", rank: 1)])])
    let orphan = ShelfItem(
        id: UUID(), brand: "x", name: "y", categorySlug: "unknown", categoryLabel: "unknown",
        domain: .makeup, packaging: .tube, rank: 1
    )
    #expect(live.rankedCount(inCategoryOf: orphan) == 0)
}

@MainActor
@Test func openingAnItemAndClosingItAgainLeavesNothingBehind() {
    let live = model([section("blush", domain: .makeup, items: [item("a")])])
    #expect(live.openItem == nil)
    live.open(item("a"))
    #expect(live.openItem != nil)
    live.closeSheet()
    #expect(live.openItem == nil)
}

// MARK: - The status line

@Test func somethingWearingInReadsAsAWeekRatherThanAsAStatus() {
    // "week 3" is the fact that matters while a product is being worn in;
    // "own" is true and says nothing.
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let wearing = ShelfItem(
        id: UUID(), brand: "rhode", name: "pineapple refresh",
        categorySlug: "cleanser", categoryLabel: "cleanser", domain: .skincare,
        packaging: .bottle, status: .own, startedOn: start
    )
    #expect(wearing.statusLabel(on: start.addingTimeInterval(15 * 86400)) == "week 3")
    #expect(wearing.statusLabel(on: start) == "week 1")
}

@Test func withNoStartDateTheStatusIsTheStatus() {
    #expect(item("a").statusLabel() == "own")
}

@Test func everyStatusHasLowercaseCopyAndNoUnderscore() {
    // `want_to_try` reaching a shelf with its underscore showing is the shape
    // of bug a rawValue tidy-up produces the first time a case is added.
    for status in [ItemStatus.wantToTry, .own, .finished, .repurchased] {
        let label = ShelfItem.label(for: status)
        #expect(!label.contains("_"))
        #expect(label == label.lowercased())
    }
    #expect(ShelfItem.label(for: .wantToTry) == "want to try")
}
