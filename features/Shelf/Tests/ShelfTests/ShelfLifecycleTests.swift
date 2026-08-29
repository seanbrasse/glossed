import DataKit
import DesignSystem
import Foundation
import Testing
@testable import Shelf

// MARK: - Helpers

private func item(_ name: String = "blush") -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: "rare beauty",
        name: name,
        categorySlug: "blush",
        categoryLabel: "blush",
        domain: .makeup,
        packaging: .dropper
    )
}

/// Records removals and answers each from a script — so a test can say
/// "fail once, then succeed" and exercise retry on the same model.
private actor LifecycleProbe {
    private(set) var removed: [UUID] = []
    private(set) var statusWrites: [(UUID, ItemStatus)] = []
    private var failures: [GlossedError?]

    init(failing failures: [GlossedError?] = [nil]) {
        self.failures = failures
    }

    func updateStatus(_ id: UUID, _ status: ItemStatus) throws(GlossedError) {
        statusWrites.append((id, status))
        let failure = failures.count > 1 ? failures.removeFirst() : failures[0]
        if let failure {
            throw failure
        }
    }

    func remove(_ id: UUID) throws(GlossedError) {
        removed.append(id)
        let failure = failures.count > 1 ? failures.removeFirst() : failures[0]
        if let failure {
            throw failure
        }
    }

    nonisolated var store: ShelfLifecycleStore {
        ShelfLifecycleStore(
            remove: { id throws(GlossedError) in
                try await self.remove(id)
            },
            updateStatus: { id, status throws(GlossedError) in
                try await self.updateStatus(id, status)
            }
        )
    }
}

@MainActor
private func model(
    _ items: [ShelfItem],
    lifecycle: ShelfLifecycleStore?,
    onShelfChanged: (() -> Void)? = nil
) -> ShelfModel {
    ShelfModel(
        sections: [ShelfSection(slug: "blush", label: "blush", domain: .makeup, items: items)],
        lifecycle: lifecycle,
        onShelfChanged: onShelfChanged
    )
}

@MainActor
struct ShelfLifecycleTests {
    @Test func removingTheOpenItemClosesTheSheetAndTellsTheHost() async {
        let opened = item()
        let probe = LifecycleProbe()
        var shelfChanged = 0
        let live = model([opened], lifecycle: probe.store) { shelfChanged += 1 }

        live.open(opened)
        live.removeOpenItem()
        await live.removeTask?.value

        #expect(await probe.removed == [opened.id])
        // Both halves of "it leaves in one motion": the sheet is gone and the
        // host was told to re-read.
        #expect(live.openItem == nil)
        #expect(shelfChanged == 1)
        #expect(live.removeFailure == nil)
    }

    @Test func aFailedRemoveKeepsTheSheetUpAndSaysWhy() async {
        let opened = item()
        let probe = LifecycleProbe(failing: [
            GlossedError(.offline, userMessage: "no connection — try again in a sec.")
        ])
        var shelfChanged = 0
        let live = model([opened], lifecycle: probe.store) { shelfChanged += 1 }

        live.open(opened)
        live.removeOpenItem()
        await live.removeTask?.value

        // A remove that silently did not happen is an item that reappears on
        // the next launch — the sheet must stay and say so.
        #expect(live.openItem?.id == opened.id)
        #expect(live.removeFailure?.code == .offline)
        #expect(shelfChanged == 0)
    }

    @Test func retryAfterAFailedRemoveCanSucceed() async {
        let opened = item()
        let probe = LifecycleProbe(failing: [
            GlossedError(.offline, userMessage: "no network"),
            nil
        ])
        let live = model([opened], lifecycle: probe.store)

        live.open(opened)
        live.removeOpenItem()
        await live.removeTask?.value
        #expect(live.removeFailure != nil)

        live.removeOpenItem()
        await live.removeTask?.value

        #expect(live.removeFailure == nil)
        #expect(live.openItem == nil)
        #expect(await probe.removed.count == 2)
    }

    @Test func openingANewSheetClearsTheOldFailure() async {
        let first = item("first")
        let second = item("second")
        let probe = LifecycleProbe(failing: [
            GlossedError(.offline, userMessage: "no network")
        ])
        let live = model([first, second], lifecycle: probe.store)

        live.open(first)
        live.removeOpenItem()
        await live.removeTask?.value
        #expect(live.removeFailure != nil)

        live.open(second)
        // A different sheet is a different conversation.
        #expect(live.removeFailure == nil)
        #expect(!live.isRemoving)
    }

    @Test func aStatusChangePersistsAndTellsTheHostWithoutClosing() async {
        let opened = item()
        let probe = LifecycleProbe()
        var shelfChanged = 0
        let live = model([opened], lifecycle: probe.store) { shelfChanged += 1 }

        live.open(opened)
        #expect(live.openStatus == .own)
        live.statusChanged(to: .finished)
        #expect(live.openStatus == .finished) // optimistic
        await live.statusTask?.value

        #expect(await probe.statusWrites.count == 1)
        #expect(await probe.statusWrites.first?.1 == .finished)
        // The sheet stays open — a status change is not a departure — and
        // the host re-read waits for close, or an immediate reload would
        // replace the model and slam the sheet shut (first-drive finding).
        #expect(live.openItem?.id == opened.id)
        #expect(shelfChanged == 0)
        live.closeSheet()
        #expect(shelfChanged == 1)
        // Close with nothing new pending notifies once, not every time.
        live.open(opened)
        live.closeSheet()
        #expect(shelfChanged == 1)
    }

    @Test func aFailedStatusWriteRevertsOnScreen() async {
        let opened = item()
        let probe = LifecycleProbe(failing: [
            GlossedError(.offline, userMessage: "no network")
        ])
        let live = model([opened], lifecycle: probe.store)

        live.open(opened)
        live.statusChanged(to: .repurchased)
        await live.statusTask?.value

        // The control never keeps showing an answer that did not persist.
        #expect(live.openStatus == .own)
    }

    @Test func settingTheSameStatusWritesNothing() async {
        let opened = item()
        let probe = LifecycleProbe()
        let live = model([opened], lifecycle: probe.store)

        live.open(opened)
        live.statusChanged(to: .own)
        await live.statusTask?.value
        #expect(await probe.statusWrites.isEmpty)
    }

    @Test func removeWithoutAStoreIsANoOp() async {
        let opened = item()
        let live = model([opened], lifecycle: nil)

        live.open(opened)
        live.removeOpenItem()
        await live.removeTask?.value

        // Fixture states run with no store at all — the sheet stays put
        // rather than pretending something was written.
        #expect(live.openItem?.id == opened.id)
        #expect(live.removeFailure == nil)
    }
}
