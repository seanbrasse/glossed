import DataKit
import Foundation
import Testing
@testable import Stylist

private func reply(_ text: String, chips: [String] = ["next"], blocks: [StylistBlock] = []) -> StylistReply {
    StylistReply(text: text, blocks: blocks, chips: chips, groundedIn: ["shelf"], toolsUsed: ["suggest_chips"])
}

private func routine() -> RoutineDraftBlock {
    let json = """
    {"title":"glass skin, morning","slot":"am","targets":[],
     "steps":[{"user_item_id":"11111111-1111-4111-8111-111111111111",
               "product_name":"a","brand_name":"b","category_label":"c","note":null}],
     "gap":null}
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(RoutineDraftBlock.self, from: Data(json.utf8))
}

@MainActor
@Test func aSendAppendsTheQuestionThenTheAnswerAndTakesTheStylistsChips() async {
    let store = StylistStore(send: { turns in
        #expect(turns.last?.role == .user)
        return reply("morning it is", chips: ["build my pm routine"])
    })
    let model = StylistModel(store: store)
    #expect(model.chips == StylistModel.starterChips)
    model.draft = "  build my am routine "
    model.sendDraft()
    #expect(model.draft.isEmpty)
    #expect(model.phase == .thinking)
    await model.sendTask?.value
    #expect(model.messages.map(\.role) == [.user, .stylist])
    #expect(model.messages[0].text == "build my am routine")
    #expect(model.messages[0].isPending == false)
    #expect(model.chips == ["build my pm routine"])
    #expect(model.phase == .idle)
}

@MainActor
@Test func theTranscriptTheServerReadsIsTextOnlyAndOldestFirst() async {
    let store = StylistStore(send: { _ in reply("ok") })
    let model = StylistModel(store: store)
    model.send("one")
    await model.sendTask?.value
    model.send("two")
    await model.sendTask?.value
    #expect(model.transcript.map(\.text) == ["one", "ok", "two", "ok"])
}

@MainActor
@Test func aFailedTurnKeepsTheWordsAndOffersARetry() async {
    let attempts = Attempts()
    let store = StylistStore(send: { _ in
        if await attempts.next() == 1 {
            throw GlossedError(.offline, userMessage: "no connection.")
        }
        return reply("there you go")
    })
    let model = StylistModel(store: store)
    model.send("compare my two serums")
    await model.sendTask?.value
    #expect(model.errorMessage == "no connection.")
    #expect(model.messages.last?.isPending == true)
    #expect(model.phase == .idle)
    model.retry()
    await model.sendTask?.value
    #expect(model.errorMessage == nil)
    #expect(model.messages.map(\.text) == ["compare my two serums", "there you go"])
}

@MainActor
@Test func notYetAndUnconfiguredAreStatesOfTheTabNotToasts() async {
    let minor = StylistModel(store: StylistStore(send: { _ in throw StylistError.notYet }))
    minor.send("hi")
    await minor.sendTask?.value
    #expect(minor.phase == .notYet)
    #expect(minor.errorMessage == nil)

    let bare = StylistModel(store: StylistStore(send: { _ in throw StylistError.unconfigured }))
    bare.send("hi")
    await bare.sendTask?.value
    #expect(bare.phase == .unconfigured)
}

@MainActor
@Test func aChipIsAMessageAndNothingActsWithoutTheTap() async {
    let store = StylistStore(send: { turns in reply("sure: \(turns.last?.text ?? "")") })
    let model = StylistModel(store: store)
    model.tap(chip: "what should I try next")
    await model.sendTask?.value
    #expect(model.messages.first?.text == "what should I try next")
}

@MainActor
@Test func savingARoutineIsOfferedOnlyWhenTheSeamExistsAndSaysSoOnce() async {
    let noSeam = StylistModel(store: StylistStore(send: { _ in reply("x") }))
    #expect(!noSeam.canSaveRoutines)

    let saves = Attempts()
    var store = StylistStore(send: { _ in reply("x") })
    store.saveRoutine = { _ in
        _ = await saves.next()
        return UUID()
    }
    let model = StylistModel(store: store)
    let draft = routine()
    model.save(routine: draft)
    #expect(model.savingRoutine == draft)
    for _ in 0 ..< 50 where model.savingRoutine != nil {
        await Task.yield()
    }
    #expect(model.savedRoutines.contains(draft))
    model.save(routine: draft)
    #expect(await saves.count == 1, "a saved routine is not saved twice")
}

@MainActor
@Test func noStoreMeansNothingSendsAndNothingCrashes() {
    let model = StylistModel(store: nil)
    model.send("hi")
    #expect(model.messages.isEmpty)
    #expect(model.phase == .idle)
}

private actor Attempts {
    private(set) var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}
