import DataKit
import Foundation
import Testing
@testable import Shelf

// GLO-166: the shelf had one designed empty state (a dry search) and rendered
// a bare screen for every other way of emptying it. Turning all four domain
// chips off — four taps — left nothing on screen and nothing said. The gap was
// even named in `searchCameUpEmpty`'s own comment: "distinct from 'every
// domain off'". It was known, described, and unhandled.
//
// Each case below is reachable by tapping, which is why each one is here.

private func item(_ name: String, _ domain: Domain, status: ItemStatus = .own) -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: "b",
        name: name,
        categorySlug: "c",
        categoryLabel: "c",
        domain: domain,
        packaging: .bottle,
        status: status
    )
}

private func section(_ domain: Domain, _ items: [ShelfItem]) -> ShelfSection {
    ShelfSection(slug: "\(domain)", label: "\(domain)", domain: domain, items: items)
}

@MainActor
private func model(
    _ sections: [ShelfSection],
    domains: Set<Domain> = [.makeup, .skincare]
) -> ShelfModel {
    ShelfModel(sections: sections, selectedDomains: domains)
}

@MainActor
struct ShelfEmptyStateTests {
    @Test func aShelfWithThingsOnItReportsNoEmptyState() {
        let live = model([section(.makeup, [item("a", .makeup)])])

        #expect(live.emptyState == nil)
    }

    @Test func everyDomainOffSaysSoAndNamesTheWayBack() {
        // The bug: four taps produced a blank screen and no explanation.
        let live = model([section(.makeup, [item("a", .makeup)])], domains: [])

        #expect(live.emptyState == .noDomains)
        #expect(live.emptyState?.message.contains("turn one back on") == true)
    }

    @Test func aDomainHoldingNothingOfYoursSaysThatInstead() {
        // Distinct from every-domain-off: a filter IS on, it just holds
        // nothing. Telling someone to turn a domain on when one already is
        // would send them looking in the wrong place.
        let live = model([section(.makeup, [item("a", .makeup)])], domains: [.fragrance])

        #expect(live.emptyState == .filteredOut)
    }

    @Test func aShelfThatIsAllWishlistExplainsTheHiddenGhosts() {
        // GLO-100 hides want-to-try by default, so someone whose shelf is
        // only intentions sees nothing at all — the most likely empty screen
        // for a real new user, and the least self-explanatory.
        let live = model([section(.makeup, [item("a", .makeup, status: .wantToTry)])])

        #expect(live.emptyState == .wishlistHidden)
        #expect(live.emptyState?.message.contains("bookmark") == true)
    }

    @Test func anEmptyShelfSaysItIsEmptyRatherThanFiltered() {
        // A new account. Blaming a filter here would be a lie.
        #expect(model([]).emptyState == .nothingLogged)
        #expect(model([section(.makeup, [])]).emptyState == .nothingLogged)
    }

    @Test func aDrySearchStillWinsOverEveryOtherReason() {
        // Order matters: what you just typed is the most recent thing you did,
        // so it is the explanation that fits.
        let live = model([section(.makeup, [item("a", .makeup)])])
        live.searchQuery = "zzzz"

        #expect(live.emptyState == .searchDry)
    }

    @Test func everyReasonNamesAWayOut() {
        // The rule the search message already followed and the bare shelf did
        // not. A dead end that does not name the way out is the failure this
        // ticket is about.
        for state in [
            ShelfEmptyState.searchDry, .noDomains, .filteredOut, .wishlistHidden, .nothingLogged
        ] {
            #expect(!state.message.isEmpty)
            let namesAWayOut = state.message.contains("+")
                || state.message.contains("turn one")
                || state.message.contains("bookmark")
                || state.message.contains("try another")
            #expect(namesAWayOut, "\(state) does not say what to do next")
        }
    }
}
