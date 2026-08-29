import DataKit
import DesignSystem
import Foundation
import Testing
import Tracking
@testable import Shelf

// GLO-72's last AC: the lifecycle events, asserted at the wire the way
// CreateRungModelTests asserts item_logged — a capturing poster reads what
// actually flushed, not a counter.

private actor CapturingPoster: EventPosting {
    private(set) var posted: [QueuedEvent] = []

    func post(_ batch: [QueuedEvent]) async throws {
        posted.append(contentsOf: batch)
    }
}

private func item(variantID: UUID? = nil, status: ItemStatus = .own) -> ShelfItem {
    ShelfItem(
        id: UUID(),
        brand: "rare beauty",
        name: "blush",
        categorySlug: "blush",
        categoryLabel: "blush",
        domain: .makeup,
        packaging: .dropper,
        status: status,
        variantID: variantID
    )
}

private struct Rig {
    let poster: CapturingPoster
    let tracker: Tracker
    let model: ShelfModel

    @MainActor
    init(_ opened: ShelfItem, failing: [GlossedError?] = [nil]) {
        let probe = ShelfLifecycleEventTests.Probe(failing: failing)
        poster = CapturingPoster()
        tracker = Tracker(poster: poster)
        model = ShelfModel(
            sections: [ShelfSection(slug: "blush", label: "blush", domain: .makeup, items: [opened])],
            lifecycle: probe.store,
            tracker: tracker
        )
        model.open(opened)
    }
}

@MainActor
struct ShelfLifecycleEventTests {
    /// The same scriptable double the lifecycle tests use, local so the two
    /// files cannot drift apart silently — this one only ever succeeds or
    /// fails per its script.
    actor Probe {
        private var failures: [GlossedError?]

        init(failing failures: [GlossedError?] = [nil]) {
            self.failures = failures
        }

        private func next() throws(GlossedError) {
            let failure = failures.count > 1 ? failures.removeFirst() : failures[0]
            if let failure {
                throw failure
            }
        }

        nonisolated var store: ShelfLifecycleStore {
            ShelfLifecycleStore(
                remove: { _ throws(GlossedError) in try await self.next() },
                updateStatus: { _, _ throws(GlossedError) in try await self.next() }
            )
        }
    }

    @Test func aLandedStatusChangeTracksBothEndsOfTheMove() async {
        let variantID = UUID()
        let rig = Rig(item(variantID: variantID))

        rig.model.statusChanged(to: .finished)
        await rig.model.statusTask?.value
        await rig.tracker.flush()

        let events = await rig.poster.posted
        #expect(events.count == 1)
        #expect(events.first?.name == "item_status_changed")
        #expect(events.first?.props["variant_id"] == .id(variantID))
        #expect(events.first?.props["from"] == .string("own"))
        #expect(events.first?.props["to"] == .string("finished"))
    }

    @Test func chainedMovesEachReportTheMoveTheyActuallyMade() async {
        // own → finished → repurchased: the second event's `from` is finished,
        // not the stale own — `from` is read after the previous write settles.
        let rig = Rig(item(variantID: UUID()))

        rig.model.statusChanged(to: .finished)
        rig.model.statusChanged(to: .repurchased)
        await rig.model.statusTask?.value
        await rig.tracker.flush()

        let events = await rig.poster.posted
        #expect(events.map { $0.props["from"] } == [.string("own"), .string("finished")])
        #expect(events.map { $0.props["to"] } == [.string("finished"), .string("repurchased")])
    }

    @Test func aFailedWriteTracksNothing() async {
        // An event is a fact: no row moved, no event says one did.
        let rig = Rig(item(variantID: UUID()), failing: [GlossedError(.offline, userMessage: "no")])

        rig.model.statusChanged(to: .finished)
        await rig.model.statusTask?.value
        rig.model.removeOpenItem()
        await rig.model.removeTask?.value
        await rig.tracker.flush()

        #expect(await rig.poster.posted.isEmpty)
    }

    @Test func aRemovalSaysWhatTheItemWasWhenItLeft() async {
        let variantID = UUID()
        let rig = Rig(item(variantID: variantID, status: .wantToTry))

        rig.model.removeOpenItem()
        await rig.model.removeTask?.value
        await rig.tracker.flush()

        let events = await rig.poster.posted
        #expect(events.first?.name == "item_removed")
        #expect(events.first?.props["variant_id"] == .id(variantID))
        #expect(events.first?.props["status"] == .string("want_to_try"))
    }

    @Test func aFixtureItemWithoutAVariantFiresNoEvent() async {
        // Picker states build items with no variant id; an event that cannot
        // name its variant would be a rollup row that joins to nothing.
        let rig = Rig(item(variantID: nil))

        rig.model.statusChanged(to: .finished)
        await rig.model.statusTask?.value
        await rig.tracker.flush()

        #expect(await rig.poster.posted.isEmpty)
    }
}
