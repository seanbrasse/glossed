import DataKit
import DesignSystem
import Foundation
import Testing
@testable import ProductPage

// GLO-47's second half. The page's fit control shipped writing nowhere, and
// its own comment said why: the write needs a `user_item_id` and the page was
// opened from a variant. #213 made the page reachable from the shelf, where
// the row's id IS the user_item_id — so the stated blocker stopped being true
// and nobody noticed.

private actor FitProbe {
    private(set) var saves: [(UUID, Set<FitAnswer>)] = []
    private(set) var loads: [UUID] = []

    func load(_ id: UUID) {
        loads.append(id)
    }

    func save(_ id: UUID, _ answers: Set<FitAnswer>) {
        saves.append((id, answers))
    }
}

private struct SaveFailed: Error {}

private func store(
    _ probe: FitProbe,
    loading saved: Set<FitAnswer> = [],
    failingSaves: Bool = false
) -> ProductFitStore {
    ProductFitStore(
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

private struct NoEvidence: ShadeEvidenceReading {
    func payoff(variantID _: UUID) async throws(GlossedError) -> PayoffEvidence {
        PayoffEvidence(exactShadeCount: 0, withFitCount: 0, evidenceBacked: false)
    }
}

@MainActor
private func page(userItemID: UUID?, store: ProductFitStore?) -> ProductPageModel {
    ProductPageModel(
        product: ProductPageItem(
            variantID: UUID(),
            brand: "fenty beauty",
            name: "pro filt'r soft matte",
            categoryLabel: "foundation",
            isAnchor: true,
            userItemID: userItemID
        ),
        aggregates: NoEvidence(),
        fitStore: store
    )
}

// MARK: - The mapping, duplicated from Shelf and therefore pinned

@Test func everyAnswerSurvivesTheRoundTripBothWays() {
    // `Shelf` owns an identical mapping and the two cannot import each other.
    // This is the guard that makes a divergence a red test rather than an
    // answer that silently never persists — see ProductFitStore's note and
    // GLO-164.
    for answer in FitAnswer.allCases {
        #expect(ProductFitStore.answer(ProductFitStore.wire(answer)) == answer)
    }
    for fit in Fit.allCases {
        #expect(ProductFitStore.wire(ProductFitStore.answer(fit)) == fit)
    }
    #expect(Fit.allCases.count == FitAnswer.allCases.count, "neither enum has an unmapped case")
}

// MARK: - The gate

@MainActor
@Test func aPageReachedWithoutOwningTheProductDoesNotOfferToSave() {
    // Search and leaderboards open this page too, and there is no shelf row
    // behind those. The answer would go nowhere, so it must not be claimed —
    // the same rule as the dead "full page" button (GLO-151).
    #expect(!page(userItemID: nil, store: store(FitProbe())).canCaptureFit)
    #expect(!page(userItemID: UUID(), store: nil).canCaptureFit)
    #expect(page(userItemID: UUID(), store: store(FitProbe())).canCaptureFit)
}

@MainActor
@Test func withoutAShelfRowNothingIsEvenRead() async {
    let probe = FitProbe()
    let model = page(userItemID: nil, store: store(probe, loading: [.tooLight]))

    model.loadFit()
    await model.fitLoadTask?.value

    #expect(await probe.loads.isEmpty)
    #expect(model.fit.isEmpty)
}

// MARK: - Reading and writing

@MainActor
@Test func theSavedAnswerComesBackOnOpen() async {
    let probe = FitProbe()
    let id = UUID()
    let model = page(userItemID: id, store: store(probe, loading: [.tooLight, .tooPink]))

    model.loadFit()
    await model.fitLoadTask?.value

    #expect(model.fit == [.tooLight, .tooPink])
    #expect(await probe.loads == [id])
}

@MainActor
@Test func answeringOnThePageWritesToTheShelfRow() async {
    // The whole point: the page and the sheet are two doors onto one row.
    let probe = FitProbe()
    let id = UUID()
    let model = page(userItemID: id, store: store(probe))

    model.fitChanged(to: [.justRight])
    await model.fitSaveTask?.value

    let saves = await probe.saves
    #expect(saves.count == 1)
    #expect(saves.first?.0 == id)
    #expect(saves.first?.1 == [.justRight])
}

@MainActor
@Test func aFailedSaveFallsBackToWhatIsPersisted() async {
    let probe = FitProbe()
    let model = page(userItemID: UUID(), store: store(probe, loading: [.tooDark], failingSaves: true))

    model.loadFit()
    await model.fitLoadTask?.value
    model.fitChanged(to: [.justRight])
    await model.fitSaveTask?.value

    #expect(model.fit == [.tooDark], "the meter may not keep claiming a write that did not happen")
}
