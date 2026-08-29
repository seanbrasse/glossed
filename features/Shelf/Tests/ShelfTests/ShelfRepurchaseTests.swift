import DataKit
import Foundation
import Testing
@testable import Shelf

// GLO-87's open question, answered: "would repurchase" is neither a new
// status nor a chip. `status == .repurchased` is what you DID; `like_state`
// is what you WOULD. Sean's own phrasing — "repurchased, would repurchase" —
// is that pair, and the two never contradict each other because they answer
// different questions. No schema change.

private func item(_ status: ItemStatus = .own) -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: "fenty beauty",
        name: "pro filt'r soft matte",
        categorySlug: "foundation",
        categoryLabel: "foundation",
        domain: .makeup,
        packaging: .compact,
        status: status
    )
}

private actor LikeProbe {
    private(set) var saves: [(UUID, RepurchaseAnswer?)] = []
    private(set) var loads: [UUID] = []

    func load(_ id: UUID) {
        loads.append(id)
    }

    func save(_ id: UUID, _ answer: RepurchaseAnswer?) {
        saves.append((id, answer))
    }
}

private struct SaveFailed: Error {}

private func store(
    _ probe: LikeProbe,
    loading saved: RepurchaseAnswer? = nil,
    failingSaves: Bool = false
) -> ShelfLikeStore {
    ShelfLikeStore(
        load: { id in
            await probe.load(id)
            return saved
        },
        save: { id, answer in
            if failingSaves {
                throw SaveFailed()
            }
            await probe.save(id, answer)
        }
    )
}

@MainActor
private func model(_ items: [ShelfItem], store: ShelfLikeStore?) -> ShelfModel {
    ShelfModel(
        sections: [ShelfSection(slug: "any", label: "any", domain: .makeup, items: items)],
        likeStore: store
    )
}

// MARK: - The translation

@Test func theColumnsThreeValuesBecomeAnAnswerOrNoAnswer() {
    // `like_state` is -1 | 0 | 1 and 0 is what "I haven't said" looks like
    // there. Nothing above this edge should have to know that.
    #expect(RepurchaseAnswer(.liked) == .yes)
    #expect(RepurchaseAnswer(.disliked) == .no)
    #expect(RepurchaseAnswer(.neutral) == nil)
}

@Test func clearingAnAnswerPersistsNeutralRatherThanDeletingIt() {
    // Deleting the row would lose the difference between "asked and shrugged"
    // and "never asked", and the aggregates read that difference.
    #expect(RepurchaseAnswer.state(for: nil) == .neutral)
    #expect(RepurchaseAnswer.state(for: .yes) == .liked)
    #expect(RepurchaseAnswer.state(for: .no) == .disliked)
}

// MARK: - The gate

@MainActor
@Test func aNeverWornItemIsNotAskedWhetherItWouldBeBoughtAgain() async {
    // The same predicate the fit gate and the chips stand behind: you cannot
    // say whether you would buy something again before you have used it.
    let probe = LikeProbe()
    let wishlist = item(.wantToTry)
    let live = model([wishlist], store: store(probe, loading: .yes))

    live.open(wishlist)
    await live.likeLoadTask?.value

    #expect(await probe.loads.isEmpty, "a want-to-try never asks the store")
    #expect(live.openRepurchase == nil)
}

@MainActor
@Test func aTriedItemLoadsWhateverWasSaid() async {
    let probe = LikeProbe()
    let owned = item(.own)
    let live = model([owned], store: store(probe, loading: .no))

    live.open(owned)
    await live.likeLoadTask?.value

    #expect(live.openRepurchase == .no)
    #expect(await probe.loads == [owned.id])
}

// MARK: - Writing

@MainActor
@Test func answeringSavesAndClearingSavesTheClearing() async {
    let probe = LikeProbe()
    let owned = item(.finished)
    let live = model([owned], store: store(probe))

    live.open(owned)
    await live.likeLoadTask?.value
    live.repurchaseChanged(to: .yes)
    await live.likeSaveTask?.value
    live.repurchaseChanged(to: nil)
    await live.likeSaveTask?.value

    let saves = await probe.saves
    #expect(saves.map(\.1) == [.yes, nil], "unanswered is a state you can return to")
    #expect(live.openRepurchase == nil)
}

@MainActor
@Test func aFailedRepurchaseSaveFallsBackToWhatIsPersisted() async {
    // The control may not keep claiming a write that did not happen — the
    // same rule the fit control and the status row already follow.
    let probe = LikeProbe()
    let owned = item(.repurchased)
    let live = model([owned], store: store(probe, loading: .yes, failingSaves: true))

    live.open(owned)
    await live.likeLoadTask?.value
    live.repurchaseChanged(to: .no)
    await live.likeSaveTask?.value

    #expect(live.openRepurchase == .yes)
}

@MainActor
@Test func withoutAStoreNothingCrashesAndNothingIsClaimed() {
    let owned = item(.own)
    let live = model([owned], store: nil)

    live.open(owned)
    live.repurchaseChanged(to: .yes)

    #expect(live.openRepurchase == .yes, "the control still moves locally")
    #expect(live.likeSaveTask == nil, "but nothing pretends to persist it")
}

// MARK: - The offer

@MainActor
@Test func withoutAStoreTheQuestionIsNotOffered() {
    // GLO-72's rule, and GLO-151's after it: a surface that cannot write must
    // not offer to. `ShelfView` reads this to decide whether to hand the sheet
    // a handler at all, and no handler means no control.
    let owned = item(.own)

    #expect(!model([owned], store: nil).supportsRepurchase)
    #expect(model([owned], store: store(LikeProbe())).supportsRepurchase)
}
