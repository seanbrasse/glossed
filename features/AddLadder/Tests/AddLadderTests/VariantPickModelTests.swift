import DataKit
import Foundation
import Testing
@testable import AddLadder

/// Variants the way the app really gets them — decoded off the wire, because
/// DataKit is frozen and `Variant`'s memberwise init is internal to it. Same
/// reasoning as `hit(name:scope:)` in SearchRungTests.
func variant(
    productID: UUID,
    shade: String? = nil,
    sizeML: Double? = nil,
    strengthPct: Double? = nil
) throws -> Variant {
    let shadeField = shade.map { "\"shade_code\":\"\($0)\"," } ?? ""
    let sizeField = sizeML.map { "\"size_ml\":\($0)," } ?? ""
    let strengthField = strengthPct.map { "\"strength_pct\":\($0)," } ?? ""
    let json = """
    {"id":"\(UUID().uuidString)","product_id":"\(productID.uuidString)",
     \(shadeField)\(sizeField)\(strengthField)"gtin":null}
    """
    return try JSONDecoder().decode(Variant.self, from: Data(json.utf8))
}

actor FakeVariantListing: VariantListing {
    /// One outcome per call, last one repeating — so a test can script
    /// "fail, then succeed" and exercise retry on the same model.
    private var outcomes: [Result<[Variant], GlossedError>]
    private(set) var asked: [UUID] = []

    init(variants: [Variant] = [], failure: GlossedError? = nil) {
        if let failure {
            outcomes = [.failure(failure)]
        } else {
            outcomes = [.success(variants)]
        }
    }

    init(outcomes: [Result<[Variant], GlossedError>]) {
        self.outcomes = outcomes
    }

    func variants(productID: UUID) async throws(GlossedError) -> [Variant] {
        asked.append(productID)
        let outcome = outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]
        return try outcome.get()
    }
}

@MainActor
struct VariantPickModelTests {
    @Test func loadingListsTheProductsOwnVariantsUnpicked() async throws {
        let picked = try hit(name: "soft pinch liquid blush")
        let shades = try ["220", "240", "330"].map {
            try variant(productID: picked.id, shade: $0, sizeML: 32)
        }
        let model = VariantPickModel(hit: picked, catalog: FakeVariantListing(variants: shades))

        await model.load()

        #expect(model.variants.count == 3)
        // Three shades is a real choice — preselecting any of them is exactly
        // the silent wrong-shade log GLO-56 warns about.
        #expect(model.selectedVariantID == nil)
        #expect(!model.canConfirm)
    }

    @Test func aSoleVariantIsPreselectedButStillNeedsTheConfirm() async throws {
        let picked = try hit(name: "pineapple refresh")
        let only = try variant(productID: picked.id, sizeML: 150)
        let model = VariantPickModel(hit: picked, catalog: FakeVariantListing(variants: [only]))

        await model.load()

        // One tap to confirm, zero taps to select — but nothing has resolved:
        // the model never logs, it only holds the answer.
        #expect(model.selectedVariantID == only.id)
        #expect(model.canConfirm)
        #expect(model.confirmed?.id == only.id)
    }

    @Test func aSoleVariantIsStatedNotAskedAbout() async throws {
        // Sean, Sep 2: "confusing when one size is the only option, and why
        // does it say yours??" — `isSole` is what the sheet reads to drop
        // the question and the marker. Before the load it is not yet known.
        let productID = UUID()
        let sole = try VariantPickModel(
            hit: hit(name: "travel spray"),
            catalog: FakeVariantListing(variants: [variant(productID: productID)])
        )
        #expect(!sole.isSole, "unknown until the list arrives")
        await sole.load()
        #expect(sole.isSole)

        let two = try VariantPickModel(
            hit: hit(name: "foundation"),
            catalog: FakeVariantListing(variants: [
                variant(productID: productID, shade: "1c"), variant(productID: productID, shade: "2n")
            ])
        )
        await two.load()
        #expect(!two.isSole)
    }

    @Test func selectingKeepsToTheListedVariants() async throws {
        let picked = try hit(name: "soft pinch liquid blush")
        let shades = try ["220", "240"].map {
            try variant(productID: picked.id, shade: $0, sizeML: 32)
        }
        let model = VariantPickModel(hit: picked, catalog: FakeVariantListing(variants: shades))
        await model.load()

        try model.select(#require(shades.last?.id))
        #expect(model.confirmed?.shadeCode == "240")

        // A stray id — a stale row, a race — must not become the confirmed
        // pick, and must not clear one either.
        model.select(UUID())
        #expect(model.confirmed?.shadeCode == "240")
    }

    @Test func aFailedLoadOffersRetryNotAnEmptyState() async throws {
        let picked = try hit(name: "cloud paint")
        let failing = FakeVariantListing(
            failure: GlossedError(.offline, userMessage: "no connection — try again in a sec.")
        )
        let model = VariantPickModel(hit: picked, catalog: failing)

        await model.load()

        #expect(model.failure != nil)
        // A failure is not evidence about the catalog: the sheet must say
        // "couldn't load", never "there is nothing here".
        #expect(!model.isEmpty)
        #expect(!model.canConfirm)
    }

    @Test func shadesReadInNumericOrderNotTextOrder() async throws {
        // The wire arrives in Postgres text order — kylie's real failure
        // ("1.5w, 10.5n, 10c, 10n, 1c") and fenty's #100-before-#98 (GLO-98).
        let picked = try hit(name: "power plush longwear foundation")
        let wireOrder = try ["1.5w", "10.5n", "10c", "10n", "1c", "2n"].map {
            try variant(productID: picked.id, shade: $0)
        }
        let model = VariantPickModel(hit: picked, catalog: FakeVariantListing(variants: wireOrder))

        await model.load()

        // Known half-step: "10.5n" lands before "10c" (the dot compares under
        // letters). The failure that mattered — whole numbers as text, 10
        // before 2 — is gone; perfect decimal-shade order would need a shade
        // grammar nobody has committed to.
        #expect(model.variants.map(\.shadeCode) == ["1.5w", "1c", "2n", "10.5n", "10c", "10n"])
    }

    @Test func aLabelLessRowSortsUnderEveryNamedShade() throws {
        let productID = UUID()
        let named = try variant(productID: productID, shade: "#100")
        let bare = try variant(productID: productID)
        #expect(VariantPickModel.readsBefore(named, bare))
        #expect(!VariantPickModel.readsBefore(bare, named))
    }

    @Test func aProductWithNoVariantsIsEmptyOnlyAfterALoadSaysSo() async throws {
        let picked = try hit(name: "an unfilled catalog row")
        let model = VariantPickModel(hit: picked, catalog: FakeVariantListing())

        // Before the load finishes there is no verdict either way.
        #expect(!model.isEmpty)
        await model.load()
        #expect(model.isEmpty)
        #expect(!model.canConfirm)
    }

    @Test func retryAfterFailureCanStillSucceed() async throws {
        let picked = try hit(name: "revealer")
        let only = try variant(productID: picked.id, shade: "6.5 n", sizeML: 30)
        let catalog = FakeVariantListing(outcomes: [
            .failure(GlossedError(.offline, userMessage: "no network")),
            .success([only])
        ])
        let model = VariantPickModel(hit: picked, catalog: catalog)

        await model.load()
        #expect(model.failure != nil)

        await model.load()
        #expect(model.failure == nil)
        #expect(model.canConfirm)
    }

    @Test func labelMatchesTheDatabasesRule() throws {
        let productID = UUID()
        // The database's own outputs for these rows: "220 · 32ml", "joy ·
        // 7.5ml", "150ml" — variant_label() in migration 0007. The trailing
        // zero on a whole size is trimmed exactly as trim_scale does.
        #expect(try variant(productID: productID, shade: "220", sizeML: 32).pickLabel == "220 · 32ml")
        #expect(try variant(productID: productID, shade: "joy", sizeML: 7.5).pickLabel == "joy · 7.5ml")
        #expect(try variant(productID: productID, sizeML: 150).pickLabel == "150ml")
        #expect(try variant(productID: productID, shade: "freckle").pickLabel == "freckle")
        #expect(try variant(productID: productID).pickLabel == nil)
        // The strength third (GLO-56's closed gap): shade · strength% · size,
        // the exact field order variant_label() concats — "10% · 30ml" for
        // the actives serum, and a whole-number strength trims its decimal.
        #expect(try variant(productID: productID, sizeML: 30, strengthPct: 10).pickLabel == "10% · 30ml")
        #expect(try variant(productID: productID, shade: "220", sizeML: 32, strengthPct: 0.5)
            .pickLabel == "220 · 0.5% · 32ml")
    }
}
