import DataKit
import Foundation
import Testing
@testable import Profile

private func text(_ body: String, _ state: ModerationState) -> PublicText {
    PublicText(kind: .linkedSocial, subjectID: nil, body: body, state: state)
}

private func store(
    load: @escaping @Sendable () async throws -> [PublicText] = { [] },
    save: @escaping @Sendable (String) async throws -> Void = { _ in }
) -> LinkedSocialsStore {
    LinkedSocialsStore(load: load, save: save)
}

@MainActor
@Test func theCopyDoesNotPromiseAReviewOrAnAppearance() async {
    // Nothing renders a linked social to anyone (GLO-189): no RPC returns one
    // and public_profile has no field for it. "not yet reviewed" implies review
    // is the only thing in the way, which is false in the reassuring direction.
    for state in [ModerationState.pending, .approved, .rejected] {
        let model = LinkedSocialsModel(store: store(load: { [text("@maya", state)] }))
        await model.load()
        #expect(model.stateLine.contains("nothing shows it to anyone yet"))
        for promise in ["reviewed", "review", "approved"] {
            #expect(!model.stateLine.contains(promise))
        }
    }
}

@MainActor
@Test func theFieldPreloadsWhatWasSaved() async {
    let model = LinkedSocialsModel(store: store(load: { [text("@maya", .pending)] }))
    await model.load()
    #expect(model.typed == "@maya")
    // And saving the same value again is refused — a no-op write would reset
    // an approved row back to pending for nothing.
    #expect(!model.canSave)
}

@MainActor
@Test func whitespaceOnlyIsNotSavable() async {
    let model = LinkedSocialsModel(store: store())
    await model.load()
    model.typed = "   "
    #expect(!model.canSave)
}

@MainActor
@Test func aChangedValueIsSavable() async {
    let model = LinkedSocialsModel(store: store(load: { [text("@maya", .approved)] }))
    await model.load()
    model.typed = "@maya_k"
    #expect(model.canSave)
}

@MainActor
@Test func savingTrimsBeforeItWrites() async {
    let captured = Captured()
    let model = LinkedSocialsModel(store: store(save: { await captured.set($0) }))
    await model.load()
    model.typed = "  @maya  "
    await model.save()
    #expect(await captured.value == "@maya")
}

@MainActor
@Test func onlyTheLinkedSocialRowIsRead() async {
    // myPublicTexts returns every kind; picking the wrong one would show a bio
    // in the socials field.
    let model = LinkedSocialsModel(store: store(load: {
        [
            PublicText(kind: .bio, subjectID: nil, body: "i like blush", state: .approved),
            text("@maya", .pending)
        ]
    }))
    await model.load()
    #expect(model.typed == "@maya")
}

private actor Captured {
    private(set) var value: String?
    func set(_ body: String) {
        value = body
    }
}
