import CoreGraphics
import Foundation
import Testing
@testable import Looks

// The composer's save path: what a failure keeps, what a retry clears, and
// the exact shape the store receives. Split from `ComposerModelTests` for the
// 300-line ceiling — the same split the source side made for the wire rows.

private func store(
    saveResult: Result<UUID, Error> = .success(UUID())
) -> LooksStore {
    LooksStore(
        save: { _, _, _ in try saveResult.get() },
        searchShelf: { _ in [] }
    )
}

private let png = Data([0x89, 0x50, 0x4E, 0x47])

/// Pins one product on `photoID` through the board — same helper as
/// `ComposerModelTests`, private to each file by the house test idiom.
@MainActor
private func pin(
    _ model: ComposerModel, on photoID: UUID, label: String,
    variantID: UUID = UUID(), x: Double = 0.5, y: Double = 0.5
) {
    let frame = CGSize(width: 300, height: 300)
    guard let spot = model.tagBoard.place(on: photoID, at: TagPoint(x: x, y: y), in: frame) else {
        Issue.record("placement was refused")
        return
    }
    model.tagBoard.add(
        TaggedProduct(variantID: variantID, label: label, category: TagCategory(slug: "t", label: "t")),
        to: spot
    )
}

@MainActor
@Test func aFailedSaveLosesNothingAndNamesItself() async {
    struct Offline: Error {}
    let model = ComposerModel(store: store(saveResult: .failure(Offline())))
    model.addPhoto(png)
    model.caption = "everything I typed"
    pin(model, on: model.photos[0].id, label: "kept")

    model.post()
    await model.saveTask?.value

    #expect(model.phase == .composing, "back to composing, not stuck saving")
    #expect(model.saveFailure != nil, "the failure names itself")
    #expect(model.caption == "everything I typed")
    #expect(model.photos.count == 1)
    #expect(model.tagBoard.taggedProductCount == 1)
    #expect(model.canPost, "the retry is live")
}

@MainActor
@Test func aRetryAfterFailureCanSucceedAndClearsTheFailure() async {
    struct Offline: Error {}
    let flaky = FlakySaver()
    let model = ComposerModel(store: LooksStore(
        save: { _, _, _ in try await flaky.attempt() },
        searchShelf: { _ in [] }
    ))
    model.addPhoto(png)

    model.post()
    await model.saveTask?.value
    #expect(model.saveFailure != nil)

    model.post()
    await model.saveTask?.value
    guard case .saved = model.phase else {
        Issue.record("expected .saved after the retry")
        return
    }
    #expect(model.saveFailure == nil)
}

@MainActor
@Test func whatTheStoreReceivesIsWhatWasComposed() async {
    let received = Captured()
    let model = ComposerModel(store: LooksStore(
        save: { caption, photos, spots in
            await received.set(caption: caption, photoCount: photos.count, spotCount: spots.count)
            return UUID()
        },
        searchShelf: { _ in [] }
    ))
    model.addPhoto(png)
    model.addPhoto(png)
    model.caption = "the drafts of us"
    pin(model, on: model.photos[1].id, label: "a", x: 0.2, y: 0.2)

    model.post()
    await model.saveTask?.value

    #expect(await received.caption == "the drafts of us")
    #expect(await received.photoCount == 2)
    #expect(await received.spotCount == 1, "the save takes SPOTS, photo identity intact")
}

// MARK: - helpers

private actor FlakySaver {
    private var calls = 0
    struct Offline: Error {}

    func attempt() throws -> UUID {
        calls += 1
        if calls == 1 {
            throw Offline()
        }
        return UUID()
    }
}

private actor Captured {
    private(set) var caption = ""
    private(set) var photoCount = 0
    private(set) var spotCount = 0

    func set(caption: String, photoCount: Int, spotCount: Int) {
        self.caption = caption
        self.photoCount = photoCount
        self.spotCount = spotCount
    }
}
