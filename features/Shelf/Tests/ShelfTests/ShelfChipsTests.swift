import DataKit
import DesignSystem
import Foundation
import Testing
@testable import Shelf

// MARK: - Helpers

private let likeChip = ShelfChip(id: UUID(), label: "lasted all day", valence: .like)
private let dislikeChip = ShelfChip(id: UUID(), label: "creased by 2pm", valence: .dislike)
private let skincareChip = ShelfChip(id: UUID(), label: "broke me out", valence: .dislike)

private func item(
    domain: Domain = .makeup,
    startedOn: Date? = nil,
    note: String? = nil
) -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: "b",
        name: "n",
        categorySlug: "c",
        categoryLabel: "c",
        domain: domain,
        packaging: .dropper,
        note: note,
        startedOn: startedOn
    )
}

/// Records every write and answers from a script, so a test can order
/// "the toggle happened" against "the store failed it".
private actor ChipProbe {
    var vocabulary: [ShelfChip]
    var applied: Set<UUID>
    var failWrites: Bool
    struct AppliedWrite {
        let itemID: UUID
        let chipID: UUID
        let startedOn: Date?
    }

    private(set) var applies: [AppliedWrite] = []
    private(set) var removes: [(UUID, UUID)] = []
    private(set) var notes: [(UUID, String)] = []

    init(vocabulary: [ShelfChip], applied: Set<UUID> = [], failWrites: Bool = false) {
        self.vocabulary = vocabulary
        self.applied = applied
        self.failWrites = failWrites
    }

    func recordApply(_ item: UUID, _ chip: UUID, _ started: Date?) throws {
        applies.append(AppliedWrite(itemID: item, chipID: chip, startedOn: started))
        if failWrites {
            throw GlossedError(.offline, userMessage: "no network")
        }
    }

    func recordRemove(_ item: UUID, _ chip: UUID) throws {
        removes.append((item, chip))
        if failWrites {
            throw GlossedError(.offline, userMessage: "no network")
        }
    }

    func recordNote(_ item: UUID, _ text: String) {
        notes.append((item, text))
    }

    nonisolated var store: ShelfChipStore {
        ShelfChipStore(
            vocabulary: { _, _ in await self.vocabulary },
            applied: { _ in await self.applied },
            apply: { item, chip, started in try await self.recordApply(item, chip, started) },
            remove: { item, chip in try await self.recordRemove(item, chip) },
            saveNote: { item, text in await self.recordNote(item, text) }
        )
    }
}

@MainActor
private func opened(
    _ probe: ChipProbe,
    on openedItem: ShelfItem
) async -> ShelfChipsModel {
    let model = ShelfChipsModel(store: probe.store)
    model.open(openedItem)
    await model.loadTask?.value
    return model
}

@MainActor
struct ShelfChipsTests {
    @Test func openingLoadsTheVocabularyAndTheAppliedSet() async {
        let probe = ChipProbe(vocabulary: [likeChip, dislikeChip], applied: [likeChip.id])
        let model = await opened(probe, on: item())

        #expect(model.vocabulary.count == 2)
        #expect(model.appliedIDs == [likeChip.id])
        #expect(model.note.isEmpty)
    }

    @Test func togglingAppliesThenRemoves() async {
        let probe = ChipProbe(vocabulary: [likeChip])
        let model = await opened(probe, on: item())

        model.toggle(likeChip.id)
        await model.chipTask?.value
        #expect(model.appliedIDs == [likeChip.id])
        #expect(await probe.applies.count == 1)

        model.toggle(likeChip.id)
        await model.chipTask?.value
        #expect(model.appliedIDs.isEmpty)
        #expect(await probe.removes.count == 1)
    }

    @Test func aFailedWriteRevertsTheChipOnScreen() async {
        let probe = ChipProbe(vocabulary: [likeChip], failWrites: true)
        let model = await opened(probe, on: item())

        model.toggle(likeChip.id)
        #expect(model.appliedIDs == [likeChip.id]) // optimistic
        await model.chipTask?.value
        // The control never keeps showing an answer that did not persist.
        #expect(model.appliedIDs.isEmpty)
    }

    @Test func aSkincareReactionWithoutAStartDateRefusesAndSaysWhy() async {
        // tech/01 §5: skincare reactions require a week; the week derives
        // from started_on. No date → no week → the chip must not save.
        let probe = ChipProbe(vocabulary: [skincareChip])
        let model = await opened(probe, on: item(domain: .skincare, startedOn: nil))

        model.toggle(skincareChip.id)
        await model.chipTask?.value

        #expect(model.needsStartDate)
        #expect(model.appliedIDs.isEmpty)
        #expect(await probe.applies.isEmpty)
    }

    @Test func aSkincareReactionWithAStartDateCarriesItToTheStore() async {
        let started = Date(timeIntervalSinceNow: -86400 * 20)
        let probe = ChipProbe(vocabulary: [skincareChip])
        let model = await opened(probe, on: item(domain: .skincare, startedOn: started))

        model.toggle(skincareChip.id)
        await model.chipTask?.value

        #expect(!model.needsStartDate)
        // The server derives the week from this — the model never types one.
        #expect(await probe.applies.first?.startedOn == started)
        #expect(model.currentWeek == 3)
    }

    @Test func theNoteSavesOnceOnCloseAndOnlyWhenItChanged() async {
        let probe = ChipProbe(vocabulary: [])
        let model = await opened(probe, on: item(note: "the boring backup"))
        #expect(model.note == "the boring backup")

        // Unchanged → no write.
        model.close()
        await model.noteTask?.value
        #expect(await probe.notes.isEmpty)

        let second = await opened(probe, on: item(note: nil))
        second.note = "never breaks me out"
        second.close()
        await second.noteTask?.value
        #expect(await probe.notes.count == 1)
        #expect(await probe.notes.first?.1 == "never breaks me out")
    }

    @Test func withoutAStoreNothingPretendsToSave() {
        let model = ShelfChipsModel(store: nil)
        model.open(item())
        model.toggle(likeChip.id)
        #expect(model.appliedIDs.isEmpty)
        #expect(!model.isLoading)
    }
}
