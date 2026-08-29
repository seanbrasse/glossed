import Foundation
import Testing
@testable import Tracking

// GLO-147: the drop is correct — analytics must never cost UX — but it was
// also silent, and a silent drop is indistinguishable from instrumentation
// that works. Three sessions in a row nearly filed a false bug on exactly
// that. These pin the voice, not the policy: the batch still dies.

private actor DropLog {
    private(set) var drops: [(count: Int, error: any Error)] = []

    func record(_ count: Int, _ error: any Error) {
        drops.append((count, error))
    }

    var counts: [Int] {
        drops.map(\.count)
    }

    var total: Int {
        counts.reduce(0, +)
    }
}

private actor DeadEndpoint: EventPosting {
    func post(_: [QueuedEvent]) async throws {
        throw URLError(.cannotConnectToHost)
    }
}

/// A post that never comes back, so the tracker stays mid-flush and the queue
/// is free to grow into its cap. The one way to reach the eviction path
/// deterministically: while `isFlushing` holds, no threshold flush can drain
/// the queue out from under the test.
private actor StalledEndpoint: EventPosting {
    func post(_: [QueuedEvent]) async throws {
        try await Task.sleep(nanoseconds: 30_000_000_000)
    }
}

private func tracker(_ log: DropLog, poster: any EventPosting = DeadEndpoint()) -> Tracker {
    Tracker(poster: poster, onDrop: { count, error in
        Task { await log.record(count, error) }
    })
}

@Test func aDeadEndpointSaysHowManyEventsItAteAndWhy() async {
    let log = DropLog()
    let live = tracker(log)
    await live.track(.shelfViewed)
    await live.track(.productViewed(productID: UUID()))
    await live.flush()

    // Give the observer's task a turn — the drop itself is synchronous, the
    // recording of it is not.
    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(await log.counts == [2])
    #expect(await live.droppedCount == 2)
    let reason = await log.drops.first?.error as? URLError
    #expect(reason?.code == .cannotConnectToHost, "the reason travels, not just the count")
    #expect(await live.pendingCount == 0, "the policy is unchanged: the batch is still gone")
}

@Test func anEndpointThatWorksDropsNothingAndSaysNothing() async {
    // The counter has to be falsifiable in both directions, or it is just
    // another number nobody can trust.
    let log = DropLog()
    let poster = CapturingPoster()
    let live = tracker(log, poster: poster)
    await live.track(.shelfViewed)
    await live.flush()

    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(await log.total == 0)
    #expect(await live.droppedCount == 0)
    #expect(await poster.batches.count == 1)
}

@Test func theCapEvictingTheOldestCountsAsADropToo() async {
    // A counter that only saw transport failures would under-report by
    // exactly the omission this ticket is about.
    let log = DropLog()
    let live = tracker(log, poster: StalledEndpoint())

    // Trip the threshold flush and let it stall, so the queue below is the
    // only thing moving.
    for _ in 0 ..< Tracker.flushThreshold {
        await live.track(.shelfViewed)
    }
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(await live.pendingCount == 0, "the stalled flush took what was queued")

    for index in 0 ..< (Tracker.capacity + 3) {
        await live.track(.exportGenerated(itemCount: index))
    }
    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(await live.pendingCount == Tracker.capacity)
    #expect(await live.droppedCount == 3)
    let overCapacity = await log.drops.compactMap { $0.error as? TrackerOverCapacity }
    #expect(overCapacity.count == 3, "one notice per shed event, each naming the cap")
    #expect(overCapacity.first?.cap == Tracker.capacity)
}

@Test func theDefaultObserverIsWiredWithoutBeingAskedFor() async {
    // The point of GLO-147 is that a driver who wired nothing still hears
    // about it, so the default must not be silence.
    let live = Tracker(poster: DeadEndpoint())
    await live.track(.shelfViewed)
    await live.flush()

    #expect(await live.droppedCount == 1)
}
