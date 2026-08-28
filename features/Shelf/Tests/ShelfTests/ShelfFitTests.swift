import DataKit
import DesignSystem
import Foundation
import Testing
@testable import Shelf

// MARK: - Helpers

private func anchorItem(_ name: String = "foundation") -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: "fenty beauty",
        name: name,
        categorySlug: "foundation",
        categoryLabel: "foundation",
        domain: .makeup,
        packaging: .bottle,
        isAnchorCategory: true
    )
}

private func plainItem() -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: "rare beauty",
        name: "blush",
        categorySlug: "blush",
        categoryLabel: "blush",
        domain: .makeup,
        packaging: .dropper
    )
}

@MainActor
private func model(_ items: [ShelfItem], store: ShelfFitStore?) -> ShelfModel {
    ShelfModel(
        sections: [ShelfSection(slug: "any", label: "any", domain: .makeup, items: items)],
        fitStore: store
    )
}

/// Records what the model asked of the store, and can hold a load open so a
/// test can order "the user edited" against "the read came back".
private actor StoreProbe {
    var loads: [UUID] = []
    var saves: [(UUID, Set<FitAnswer>)] = []
    private var heldLoads: [CheckedContinuation<Void, Never>] = []
    private var holdingLoads = false

    func holdLoads() {
        holdingLoads = true
    }

    func releaseLoads() {
        holdingLoads = false
        heldLoads.forEach { $0.resume() }
        heldLoads = []
    }

    func load(_ id: UUID) async {
        loads.append(id)
        if holdingLoads {
            await withCheckedContinuation { heldLoads.append($0) }
        }
    }

    func save(_ id: UUID, _ answers: Set<FitAnswer>) {
        saves.append((id, answers))
    }
}

private struct SaveFailed: Error {}

private func store(
    _ probe: StoreProbe,
    loading saved: Set<FitAnswer> = [],
    failingSaves: Bool = false
) -> ShelfFitStore {
    ShelfFitStore(
        load: { id in
            await probe.load(id)
            return saved
        },
        save: { id, answers in
            if failingSaves {
                throw SaveFailed()
            }
            await probe.save(id, answers)
        }
    )
}

// MARK: - The translation

@Test func everyWireFitHasExactlyOneControlAnswer() {
    // Round-tripping every case both ways proves the two enums cover each
    // other; the switches themselves make a missing case a compile error.
    for fit in Fit.allCases {
        #expect(Fit(answer: fit.answer) == fit)
    }
    #expect(Set(Fit.allCases.map(\.answer)).count == FitAnswer.allCases.count)
}

// MARK: - Loading

@MainActor
@Test func openingAnAnchorItemShowsItsSavedAnswer() async {
    let probe = StoreProbe()
    let item = anchorItem()
    let live = model([item], store: store(probe, loading: [.tooLight, .tooPink]))

    live.open(item)
    await live.fitLoadTask?.value

    #expect(live.openFit == [.tooLight, .tooPink])
    #expect(await probe.loads == [item.id])
}

@MainActor
@Test func aNonAnchorItemNeverAsksTheStore() {
    // Shade is only evidence where it is meant to match skin; the sheet has no
    // fit section for a blush and the model should not read one either.
    let probe = StoreProbe()
    let item = plainItem()
    let live = model([item], store: store(probe, loading: [.tooDark]))

    live.open(item)

    #expect(live.fitLoadTask == nil)
    #expect(live.openFit.isEmpty)
}

@MainActor
@Test func anEditBeatsAReadThatComesBackAfterIt() async {
    let probe = StoreProbe()
    let item = anchorItem()
    let live = model([item], store: store(probe, loading: [.tooDark]))

    await probe.holdLoads()
    live.open(item)
    live.fitChanged(to: [.justRight])
    await probe.releaseLoads()
    await live.fitLoadTask?.value

    // The user's answer is newer than what the read returned.
    #expect(live.openFit == [.justRight])
}

@MainActor
@Test func openingAnotherItemStartsClean() async {
    let probe = StoreProbe()
    let first = anchorItem("first")
    let second = plainItem()
    let live = model([first, second], store: store(probe, loading: [.tooDark]))

    live.open(first)
    await live.fitLoadTask?.value
    live.open(second)

    #expect(live.openFit.isEmpty)
}

// MARK: - Saving

@MainActor
@Test func changingTheFitSavesTheWholeSet() async {
    let probe = StoreProbe()
    let item = anchorItem()
    let live = model([item], store: store(probe))

    live.open(item)
    await live.fitLoadTask?.value
    live.fitChanged(to: [.tooLight, .tooYellow])
    await live.fitSaveTask?.value

    let saves = await probe.saves
    #expect(saves.count == 1)
    #expect(saves.first?.0 == item.id)
    #expect(saves.first?.1 == [.tooLight, .tooYellow])
    #expect(live.openFit == [.tooLight, .tooYellow])
}

@MainActor
@Test func aFailedSaveFallsBackToTheLastPersistedAnswer() async {
    let probe = StoreProbe()
    let item = anchorItem()
    let live = model([item], store: store(probe, loading: [.tooDark], failingSaves: true))

    live.open(item)
    await live.fitLoadTask?.value
    live.fitChanged(to: [.justRight])
    await live.fitSaveTask?.value

    // The write did not happen, so the control may not keep claiming it did.
    #expect(live.openFit == [.tooDark])
}

@MainActor
@Test func withoutAStoreTheControlStillWorks() {
    // Fixture states pass no store; the control edits locally and nothing
    // crashes or spins.
    let item = anchorItem()
    let live = model([item], store: nil)

    live.open(item)
    live.fitChanged(to: [.tooOrange])

    #expect(live.openFit == [.tooOrange])
    #expect(live.fitSaveTask == nil)
}
