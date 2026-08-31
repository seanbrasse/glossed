import DataKit
import Foundation
import Testing
@testable import Profile

// The words the profile grid wears (GLO-261). Split from
// `ProfileTabsModelTests.swift` at the 300-line ceiling.

private func step(_ position: Int, _ brand: String, _ product: String, _ shade: String? = nil) -> RoutineStep {
    RoutineStep(
        position: position, userItemID: UUID(), brandName: brand,
        productName: product, variantLabel: shade
    )
}

private func routine(
    slot: RoutineSlot = .am, startedOn: Date? = nil, steps: [RoutineStep] = []
) -> MyRoutine {
    MyRoutine(
        routineID: UUID(), title: "morning glass skin", slot: slot,
        visibility: .onlyYou, startedOn: startedOn, createdAt: Date(timeIntervalSince1970: 0), steps: steps
    )
}

/// 1 March 2026, 00:00 UTC — a Postgres `date` as the decoder hands it over.
private let marchFirst = Date(timeIntervalSince1970: 1_772_323_200)

@Test func theProductsLineIsSingularForOne() {
    #expect(ProfileCardCopy.productsLine(0) == "0 products")
    #expect(ProfileCardCopy.productsLine(1) == "1 product")
    #expect(ProfileCardCopy.productsLine(12) == "12 products")
}

@MainActor
@Test func anUnknownCoverTintDrawsUntintedRatherThanFailing() {
    // `collections.cover_tint` is nullable text with no check constraint, so
    // the column will accept anything. A cosmetic value must never be able to
    // take the grid down.
    #expect(CollectionCard.tint("butter") == .butter)
    #expect(CollectionCard.tint("cherry") == .cherry)
    #expect(CollectionCard.tint("mint") == .mint)
    #expect(CollectionCard.tint("lilac") == .lilac)
    #expect(CollectionCard.tint(nil) == .plain)
    #expect(CollectionCard.tint("chartreuse") == .plain)
}

@Test func theStepsLineCountsStepsAndNamesTheSlot() {
    #expect(
        ProfileCardCopy.stepsLine(routine(slot: .am, steps: [step(0, "cosrx", "snail mucin")]))
            == "1 step · am"
    )
    #expect(ProfileCardCopy.stepsLine(routine(slot: .pm, steps: [])) == "0 steps · pm")
}

@Test func theStepsLineAddsSinceOnlyWhenAStartDateExists() {
    // `started_on` is a Postgres `date`. Formatted in the device's zone it
    // walks back a month for anyone west of Greenwich, so the formatter is
    // pinned to UTC.
    #expect(ProfileCardCopy.sinceWord(nil) == nil)
    #expect(ProfileCardCopy.sinceWord(marchFirst) == "mar 2026")
    #expect(
        ProfileCardCopy.stepsLine(routine(slot: .washDay, startedOn: marchFirst))
            == "0 steps · wash day · since mar 2026"
    )
}

@Test func theSlotWearsTheKitsWordsNotDataKitsLabel() {
    // GLO-210: `RoutineSlot.label` says morning/evening, the kit says am/pm.
    // Delete this mapping — and this test — when the DataKit fix lands.
    #expect(RoutineSlot.am.label == "morning")
    #expect(ProfileCardCopy.slotWord(.am) == "am")
    #expect(ProfileCardCopy.slotWord(.pm) == "pm")
    #expect(ProfileCardCopy.slotWord(.weekly) == "weekly")
    #expect(ProfileCardCopy.slotWord(.washDay) == "wash day")
}

@Test func aStepNamesTheThingYouOwnAndSkipsTheShadeWhenThereIsNone() {
    #expect(ProfileCardCopy.stepLine(step(0, "cosrx", "snail mucin")) == "cosrx · snail mucin")
    #expect(
        ProfileCardCopy.stepLine(step(1, "fenty", "pro filt'r", "240"))
            == "fenty · pro filt'r · 240"
    )
}
