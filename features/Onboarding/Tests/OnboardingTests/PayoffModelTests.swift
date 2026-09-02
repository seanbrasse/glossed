import DataKit
import Foundation
import Testing
import Tracking
@testable import Onboarding

// PRD §06·6's gate, with fixtures on BOTH sides of it (the session-12
// rule): backed evidence, thin evidence, no anchor, and a failed read.

private func evidence(_ exact: Int, fit: Int, backed: Bool) throws -> PayoffEvidence {
    let raw = Data("""
    {"n_exact_shade":\(exact),"n_with_fit":\(fit),"evidence_backed":\(backed)}
    """.utf8)
    return try JSONDecoder().decode(PayoffEvidence.self, from: raw)
}

private let anchored = PayoffModel.Anchor(brand: "fenty beauty", shadeCode: "240", variantID: UUID())

@MainActor
@Test func backedEvidenceRunsTheClaim() async throws {
    let backed = try evidence(12, fit: 9, backed: true)
    let model = PayoffModel(anchor: anchored, payoff: { _ in backed })
    model.load()
    await model.loadTask?.value
    #expect(model.phase == .backed(backed))
}

@MainActor
@Test func thinEvidenceStaysQuietEvenWithNonZeroCounts() async throws {
    // the wrong side of the gate: people exist, but the RPC says the claim
    // cannot be made — a count comparison here would re-derive the gate
    let thin = try evidence(3, fit: 1, backed: false)
    let model = PayoffModel(anchor: anchored, payoff: { _ in thin })
    model.load()
    await model.loadTask?.value
    #expect(model.phase == .neutral)
}

@MainActor
@Test func noAnchorIsNeutralByConstruction() async {
    // "not listed" / no foundation: nothing to ask about, no RPC call made
    let unanchored = PayoffModel.Anchor(brand: "other", shadeCode: "not listed", variantID: nil)
    let model = PayoffModel(anchor: unanchored, payoff: { _ in
        Issue.record("the RPC must not be asked about a nil variant")
        throw URLError(.badURL)
    })
    model.load()
    await model.loadTask?.value
    #expect(model.phase == .neutral)
}

@MainActor
@Test func aFailedReadIsNeutralNotAnError() async {
    // never "couldn't check" on the payoff — a failed read and thin
    // evidence are the same honest silence before signup
    let model = PayoffModel(anchor: anchored, payoff: { _ in throw URLError(.timedOut) })
    model.load()
    await model.loadTask?.value
    #expect(model.phase == .neutral)
}

@MainActor
@Test func noStoreIsNeutralQuietly() {
    let model = PayoffModel(anchor: anchored, payoff: nil)
    model.load()
    #expect(model.phase == .neutral)
}

// ── the example shelf ──────────────────────────────────────────────────────

private func pick(_ name: String, n: Int?) -> PayoffModel.ShelfPick {
    PayoffModel.ShelfPick(id: UUID(), brand: "brand", name: name, categorySlug: "mascara", nUsers: n)
}

@MainActor
@Test func theShelfLoadsBesideTheClaimAndIsAnExampleUnlessEveryTileHasItsN() async {
    let model = PayoffModel(anchor: nil, sampleShelf: { [pick("one", n: 12), pick("two", n: nil)] })
    model.load()
    await model.shelfTask?.value
    #expect(model.shelf.count == 2)
    #expect(!model.shelfIsRanked, "one tile without an n makes the whole shelf an example")
    #expect(PayoffModel.shelfEyebrow(isRanked: model.shelfIsRanked) == "A SHELF, FOR EXAMPLE")

    let ranked = PayoffModel(anchor: nil, sampleShelf: { [pick("one", n: 12), pick("two", n: 3)] })
    ranked.load()
    await ranked.shelfTask?.value
    #expect(ranked.shelfIsRanked)
    #expect(PayoffModel.shelfEyebrow(isRanked: true) == "WHAT PEOPLE ARE LOGGING")
}

@MainActor
@Test func aFailedShelfReadIsAnEmptyShelfNotAnError() async {
    let model = PayoffModel(anchor: nil, sampleShelf: { throw URLError(.timedOut) })
    model.load()
    await model.shelfTask?.value
    #expect(model.shelf.isEmpty)
    #expect(!model.shelfIsRanked)
}

@Test func aTilesLineIsItsNOrNothing() {
    #expect(PayoffModel.shelfLine(pick("one", n: 12)) == "12 rank it")
    #expect(PayoffModel.shelfLine(pick("one", n: nil)) == nil)
}

// ── the words ──────────────────────────────────────────────────────────────

@Test func theWordsCarryTheirNumbersAndNames() {
    #expect(PayoffModel.headline(exactShadeCount: 12) == "12 people wear\nyour exact shade")
    #expect(PayoffModel.anchorBadge(anchored) == "fenty beauty 240 · your anchor")
    #expect(PayoffModel.footerLine(anchored)
        == "no tone bands, no averages — these are people in fenty beauty 240")
}

// ── the event ──────────────────────────────────────────────────────────────

private actor CapturingPoster: EventPosting {
    private(set) var posted: [QueuedEvent] = []
    func post(_ batch: [QueuedEvent]) async throws {
        posted.append(contentsOf: batch)
    }
}

@MainActor
@Test func theEventReportsBothSidesOfTheGate() async throws {
    let poster = CapturingPoster()
    let tracker = Tracker(poster: poster)
    let backed = try evidence(12, fit: 9, backed: true)
    let model = PayoffModel(anchor: anchored, payoff: { _ in backed }, tracker: tracker)
    model.load()
    await model.loadTask?.value

    let neutral = PayoffModel(anchor: nil, payoff: nil, tracker: tracker)
    neutral.load()

    try await Task.sleep(for: .milliseconds(50))
    await tracker.flush()
    let events = await poster.posted.filter { $0.name == "onb_payoff_shown" }
    #expect(events.count == 2) // one per resolution, backed and neutral alike
}
