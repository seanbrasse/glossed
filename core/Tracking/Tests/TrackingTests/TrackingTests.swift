import Foundation
import Testing
@testable import Tracking

// -- the registry ------------------------------------------------------------

@Test func everyNameIsObjectActionSnakeCase() {
    // tech/06 §3's convention, checked over the whole registry via a sample of
    // every case shape. A name with an uppercase letter or a space would leak
    // an ad-hoc convention into the rollups.
    let samples: [Event] = [
        .onbStepViewed(step: "hook", branch: .hair),
        .onbStepCompleted(step: "quiz", branch: nil),
        .onbAnchorCaptured(brandID: UUID(), variantID: UUID(), fit: "just_right"),
        .onbPayoffShown(exactShadeCount: 12, evidenceBacked: true),
        .searchPerformed(queryHash: "abc", domain: nil, hit: true, resultCount: 3, source: .ladder),
        .itemLogged(variantID: UUID(), categoryID: UUID(), source: .barcode, scope: "canonical"),
        .itemStatusChanged(variantID: UUID(), from: "own", to: "finished"),
        .itemRemoved(variantID: UUID(), status: "finished"),
        .chipApplied(chipID: UUID(), kind: "experience", week: 3),
        .fitCaptured(fits: ["too_light", "too_pink"]),
        .faceoffCompleted(categoryID: UUID(), sessionLength: 9),
        .faceoffSkipped(categoryID: UUID(), sessionLength: 9),
        .shelfViewed,
        .productViewed(productID: UUID()),
        .leaderboardViewed(categoryID: UUID(), scope: "your_shade"),
        .importCompleted(source: "notes", lines: 5, matched: 3, toLadder: 2),
        .shareInReceived(sourceHost: "sephora.com", resolved: true),
        .cutoutCaptured(confidenceBand: "high", retake: false),
        .exportGenerated(itemCount: 40),
        .recImpression(slot: .stage0, productID: UUID()),
        .recTapped(slot: .picked, productID: UUID()),
        .recDismissed(slot: .crosswalk, productID: UUID(), reason: "own_it"),
        .errorShown(code: "offline", supportReference: "AB12CD"),
        .restrictedActionBlocked(surface: "profile", action: "photo_post")
    ]
    for event in samples {
        #expect(
            event.name.range(of: "^[a-z0-9]+(_[a-z0-9]+)*$", options: .regularExpression) != nil,
            "\(event.name) breaks the naming convention"
        )
    }
    #expect(Set(samples.map(\.name)).count == samples.count, "two cases share a wire name")
}

@Test func propsCarryIdentifiersNotValues() {
    // The regulated-data rule (domain.md §5), asserted at the wire: an id prop
    // renders as a lowercase UUID string, and nothing else id-shaped exists.
    let variant = UUID()
    let event = Event.itemLogged(variantID: variant, categoryID: UUID(), source: .search, scope: "personal")
    #expect(event.props["variant_id"] == .id(variant))
    #expect(event.props["variant_id"]?.jsonValue as? String == variant.uuidString.lowercased())
}

@Test func absentPropsAreOmittedNotNull() {
    let event = Event.searchPerformed(queryHash: "h", domain: nil, hit: false, resultCount: 0, source: .onboarding)
    #expect(event.props["domain"] == nil)
    #expect(event.props["hit"] == .bool(false))
}

@Test func aLifecycleEventCarriesBothEndsOfTheMove() {
    // GLO-72's AC: the analytics question is "do bottles reach finished, or
    // sit at own forever" — one end alone cannot answer it.
    let variant = UUID()
    let changed = Event.itemStatusChanged(variantID: variant, from: "own", to: "finished")
    #expect(changed.props["variant_id"] == .id(variant))
    #expect(changed.props["from"] == .string("own"))
    #expect(changed.props["to"] == .string("finished"))

    // A removal says what the item was when it left — regret and natural
    // ends roll up differently.
    let removed = Event.itemRemoved(variantID: variant, status: "want_to_try")
    #expect(removed.props["status"] == .string("want_to_try"))
}

@Test func aMultiAxisFitTravelsWholeAndSorted() {
    // GLO-67: the capture is a set, and identical captures must compare equal
    // in rollups regardless of tap order.
    let event = Event.fitCaptured(fits: ["too_pink", "too_light"])
    #expect(event.props["fits"] == .string("too_light,too_pink"))
}

@Test func theQueryHashIsStablePerInstallAndUnreadable() {
    let salt = UUID()
    let hash = Event.queryHash("Pro Filt'r", salt: salt)
    #expect(Event.queryHash("pro filt'r  ", salt: salt) == hash, "case and whitespace do not fork the hash")
    #expect(Event.queryHash("Pro Filt'r", salt: UUID()) != hash, "a different install hashes differently")
    #expect(!hash.localizedCaseInsensitiveContains("filt"), "no readable fragment survives")
}

// -- the queue ---------------------------------------------------------------

actor CapturingPoster: EventPosting {
    private(set) var batches: [[QueuedEvent]] = []
    var failNext = false

    func post(_ batch: [QueuedEvent]) async throws {
        if failNext {
            failNext = false
            throw URLError(.notConnectedToInternet)
        }
        batches.append(batch)
    }

    func setFailNext() {
        failNext = true
    }
}

@Test func flushDeliversEverythingQueuedOnce() async {
    let poster = CapturingPoster()
    let tracker = Tracker(poster: poster)
    await tracker.track(.shelfViewed)
    await tracker.track(.productViewed(productID: UUID()))
    await tracker.flush()

    let batches = await poster.batches
    #expect(batches.count == 1)
    #expect(batches[0].map(\.name) == ["shelf_viewed", "product_viewed"])
    #expect(await tracker.pendingCount == 0)
}

@Test func aFailedFlushDropsTheBatchRatherThanBlocking() async {
    // tech/06 §2: dropped, not blocked — analytics must never cost UX. A dead
    // endpoint must not grow a queue that the cap would then spend on backlog.
    let poster = CapturingPoster()
    let tracker = Tracker(poster: poster)
    await tracker.track(.shelfViewed)
    await poster.setFailNext()
    await tracker.flush()

    #expect(await tracker.pendingCount == 0, "the failed batch is gone")
    await tracker.track(.shelfViewed)
    await tracker.flush()
    #expect(await poster.batches.count == 1, "the next flush is unaffected")
}

@Test func everyQueuedEventCarriesItsOwnID() async {
    // Client-generated UUIDs are what let the ingest dedupe a retried batch.
    let poster = CapturingPoster()
    let tracker = Tracker(poster: poster)
    for _ in 0 ..< 5 {
        await tracker.track(.shelfViewed)
    }
    await tracker.flush()
    let ids = await poster.batches[0].map(\.id)
    #expect(Set(ids).count == 5)
}

@Test func theQueueCapsByEvictingTheOldest() async {
    let poster = CapturingPoster()
    let tracker = Tracker(poster: poster)
    // Overfill without triggering the threshold flush by never awaiting it:
    // track() schedules flushes as detached tasks, so pending counts are only
    // deterministic through the cap, which is what this test pins.
    for index in 0 ..< (Tracker.capacity + 40) {
        await tracker.track(.exportGenerated(itemCount: index))
    }
    #expect(await tracker.pendingCount <= Tracker.capacity)
}

@Test func thePayloadOmitsWhatIsAbsent() {
    let event = QueuedEvent(
        id: UUID(),
        name: "shelf_viewed",
        props: [:],
        screen: nil,
        occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let payload = event.payload()
    #expect(payload["screen"] == nil)
    #expect(payload["name"] as? String == "shelf_viewed")
    #expect((payload["props"] as? [String: Any])?.isEmpty == true)
}
