import DataKit
import Foundation
import Testing
import Tracking
@testable import AddLadder

// MARK: - Stubs

/// DataKit's wire types have no public memberwise inits — they are decoded, the
/// same way `SearchRungTests.hit(name:)` builds a CatalogHit.
private func decoded<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private func fixtureCreated() throws -> CreatedProduct {
    try decoded("""
    {"product_id":"aaaaaaaa-0000-0000-0000-000000000001",
     "variant_id":"aaaaaaaa-0000-0000-0000-000000000002"}
    """)
}

/// Records every write and can be told to fail either half — the seams the
/// rung's whole design is about.
private actor CreateProbe {
    var createdDrafts: [PersonalProductDraft] = []
    var loggedDrafts: [LogDraft] = []
    var failCreate = false
    var failLog = false
    let created: CreatedProduct

    init(created: CreatedProduct) {
        self.created = created
    }

    func set(failCreate: Bool? = nil, failLog: Bool? = nil) {
        if let failCreate {
            self.failCreate = failCreate
        }
        if let failLog {
            self.failLog = failLog
        }
    }

    func recordCreate(_ draft: PersonalProductDraft) throws(GlossedError) -> CreatedProduct {
        if failCreate {
            throw GlossedError(.offline, userMessage: "no network")
        }
        createdDrafts.append(draft)
        return created
    }

    func recordLog(_ draft: LogDraft) throws(GlossedError) {
        if failLog {
            throw GlossedError(.offline, userMessage: "no network")
        }
        loggedDrafts.append(draft)
    }
}

private struct StubCatalog: ProductCreating {
    let probe: CreateProbe
    var brandRows: [Brand] = []
    var categoryRows: [DataKit.Category] = []

    func brands(matching _: String, limit _: Int) async throws(GlossedError) -> [Brand] {
        brandRows
    }

    func categories(domain _: Domain?) async throws(GlossedError) -> [DataKit.Category] {
        categoryRows
    }

    func createPersonalProduct(_ draft: PersonalProductDraft) async throws(GlossedError) -> CreatedProduct {
        try await probe.recordCreate(draft)
    }
}

private struct StubShelf: ItemLogging {
    let probe: CreateProbe

    func log(_ draft: LogDraft) async throws(GlossedError) -> UserItem {
        try await probe.recordLog(draft)
        // The model never reads the returned row; a decoded fixture would be
        // testing the fixture.
        let raw = Data("""
        {"id":"\(UUID().uuidString)","user_id":"\(UUID().uuidString)",
         "variant_id":"\(draft.variantID.uuidString)","status":"own",
         "started_on":null,"note":null,"cutout_r2_key":null}
        """.utf8)
        guard let item = try? JSONDecoder().decode(UserItem.self, from: raw) else {
            throw GlossedError(.unknown, userMessage: "stub row failed to decode")
        }
        return item
    }
}

/// Receives what the tracker flushes, so a test can read the actual wire
/// events rather than trusting a counter.
private actor CapturingPoster: EventPosting {
    var posted: [QueuedEvent] = []

    func post(_ batch: [QueuedEvent]) async throws {
        posted.append(contentsOf: batch)
    }
}

private func blushCategory() throws -> DataKit.Category {
    try decoded("""
    {"id":"bbbbbbbb-0000-0000-0000-000000000001","domain":"makeup","slug":"blush",
     "label":"blush","wear_in_days":0,"is_anchor":false,"rank_unlock_min":3}
    """)
}

private func rareBeauty() throws -> Brand {
    try decoded("""
    {"id":"cccccccc-0000-0000-0000-000000000001","name":"rare beauty"}
    """)
}

@MainActor
private func probeAndFilledModel(
    ladder: Ladder = Ladder(query: "soft pinch liquid blush"),
    tracker: Tracker? = nil
) throws -> (CreateProbe, CreateRungModel) {
    let probe = try CreateProbe(created: fixtureCreated())
    let brand = try rareBeauty()
    let category = try blushCategory()
    let live = CreateRungModel(
        catalog: StubCatalog(probe: probe, brandRows: [brand], categoryRows: [category]),
        shelf: StubShelf(probe: probe),
        ladder: ladder,
        tracker: tracker
    )
    live.pick(brand: brand)
    live.pick(category: category)
    return (probe, live)
}

// MARK: - The form's rules

@MainActor
@Test func theQueryArrivesPreFilledAsTheProductName() throws {
    let probe = try CreateProbe(created: fixtureCreated())
    let live = CreateRungModel(
        catalog: StubCatalog(probe: probe),
        shelf: StubShelf(probe: probe),
        ladder: Ladder(query: "  soft   pinch ")
    )
    #expect(live.productName == "soft pinch")
}

@MainActor
@Test func nothingSubmitsUntilBrandNameAndCategoryExist() throws {
    let probe = try CreateProbe(created: fixtureCreated())
    let live = try CreateRungModel(
        catalog: StubCatalog(probe: probe, categoryRows: [blushCategory()]),
        shelf: StubShelf(probe: probe),
        ladder: Ladder(query: "soft pinch")
    )
    #expect(!live.canCreate)
    try live.pick(brand: rareBeauty())
    #expect(!live.canCreate)
    try live.pick(category: blushCategory())
    #expect(live.canCreate)
    live.productName = "   "
    #expect(!live.canCreate)
}

@MainActor
@Test func typingAfterPickingABrandUnpicksIt() throws {
    let (_, live) = try probeAndFilledModel()
    #expect(live.pickedBrand?.name == "rare beauty")
    live.brandQuery = "rare beaut"
    // The field and the draft may never disagree about the brand.
    #expect(live.pickedBrand == nil)
    #expect(!live.canCreate)
}

// MARK: - Create + log

@MainActor
@Test func createThenLogResolvesTheLadderOntoConfirm() async throws {
    let (probe, live) = try probeAndFilledModel()
    live.variantText = "  joy ·  2.5ml mini "

    await live.create()

    let drafts = await probe.createdDrafts
    #expect(drafts.count == 1)
    #expect(drafts.first?.variant == "joy · 2.5ml mini")
    let logs = await probe.loggedDrafts
    #expect(logs.first?.variantID == probe.created.variantID)
    #expect(live.ladder.rung == .confirm)
    #expect(live.ladder.resolution == .created(productID: probe.created.productID))
    #expect(live.confirmedMeta?.variant == "joy · 2.5ml mini")
}

@MainActor
@Test func aShelvedCreateTracksItemLoggedWithTheDraftsCategory() async throws {
    // GLO-80's first real call site: the event fires when the write lands,
    // carries the created variant and the *draft's* category id, and names
    // its door. No event without a shelf row — analytics reports facts.
    let poster = CapturingPoster()
    let tracker = Tracker(poster: poster)
    let (probe, live) = try probeAndFilledModel(tracker: tracker)

    await live.create()
    await tracker.flush()

    let categoryID = try blushCategory().id
    let event = try #require(await poster.posted.first)
    #expect(await poster.posted.count == 1)
    #expect(event.name == "item_logged")
    #expect(event.props["variant_id"] == .id(probe.created.variantID))
    #expect(event.props["category_id"] == .id(categoryID))
    #expect(event.props["source"] == .string("ladder_create"))
    #expect(event.props["scope"] == .string("personal"))
}

@MainActor
@Test func aFailedLogTracksNothing() async throws {
    // The quiet-failure path (created but not shelved): no row, no event.
    let poster = CapturingPoster()
    let tracker = Tracker(poster: poster)
    let (probe, live) = try probeAndFilledModel(tracker: tracker)
    await probe.set(failLog: true)

    await live.create()
    await tracker.flush()

    #expect(await poster.posted.isEmpty)
}

@MainActor
@Test func theScannedCodeRidesTheDraft() async throws {
    var ladder = Ladder(entry: .barcode)
    ladder.scanMissed(gtin: "0850000000004")
    ladder.noneOfThese()
    let (probe, live) = try probeAndFilledModel(ladder: ladder)
    live.productName = "knot today"

    await live.create()

    #expect(await probe.createdDrafts.first?.scannedGTIN == "0850000000004")
}

@MainActor
@Test func aFailedCreateLeavesNothingAndCanRetryWhole() async throws {
    let (probe, live) = try probeAndFilledModel()
    await probe.set(failCreate: true)

    await live.create()

    #expect(live.failure != nil)
    #expect(live.ladder.resolution == nil)
    #expect(await probe.loggedDrafts.isEmpty)

    await probe.set(failCreate: false)
    await live.create()
    #expect(live.ladder.rung == .confirm)
    #expect(await probe.createdDrafts.count == 1)
}

@MainActor
@Test func aFailedLogRetriesTheLogAloneWithTheSameShelfRow() async throws {
    // The GLO-15 quiet failure: create landed, log did not. The retry must
    // not create a second product, and the log's idempotency key must not
    // change — a retry is the same submission, not a new one.
    let (probe, live) = try probeAndFilledModel()
    await probe.set(failLog: true)

    await live.create()

    #expect(live.failure != nil)
    #expect(live.ladder.resolution == nil)
    #expect(await probe.createdDrafts.count == 1)

    await probe.set(failLog: false)
    await live.create()

    #expect(live.ladder.rung == .confirm)
    #expect(await probe.createdDrafts.count == 1)
    let logs = await probe.loggedDrafts
    #expect(logs.count == 1)
}

@MainActor
@Test func anEmptyVariantIsAbsentNotEmpty() async throws {
    let (probe, live) = try probeAndFilledModel()
    live.variantText = "   "

    await live.create()

    #expect(await probe.createdDrafts.first?.variant == nil)
    #expect(live.confirmedMeta?.variant == nil)
}
