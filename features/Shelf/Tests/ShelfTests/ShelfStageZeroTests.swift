import DataKit
import Foundation
import Testing
@testable import Shelf

// The cold-start shelf (GLO-211). The rules here are about what a pick is
// allowed to claim, which is the whole reason this screen exists rather than
// a sentence.

private func hit(basis: DiscoverHit.Basis, n: Int) throws -> DiscoverHit {
    let json = """
    {"id":"\(UUID().uuidString)","name":"soft pinch liquid blush","brand_name":"rare beauty",
     "category_id":"\(UUID().uuidString)","category_slug":"blush","domain":"makeup",
     "scope":"canonical","basis":"\(basis.rawValue)","basis_n":\(n)}
    """
    return try JSONDecoder().decode(DiscoverHit.self, from: Data(json.utf8))
}

@Test func aPickCarriesItsNAndSaysWhy() throws {
    let pick = try #require(StageZeroPick(hit: hit(basis: .shade, n: 12)))
    #expect(pick.n == 12)
    #expect(pick.reason == "people in your shade kept it")
    #expect(pick.brand == "rare beauty")
}

@Test func theWanderIsDroppedRatherThanRenderedWithoutEvidence() throws {
    // exploration's basisN is 0 by construction — it is the labelled wander
    // against the filter bubble and claims no evidence. On a screen whose job
    // is "here is why we think you'll keep this", a row that cannot say why
    // is worse than one row fewer.
    #expect(try StageZeroPick(hit: hit(basis: .exploration, n: 0)) == nil)
}

@Test func aPickWithNoNIsDroppedWhateverItsBasis() throws {
    // Every claim in UI copy carries its n. A zero-n row would render an
    // EvidenceLine saying nothing backs it, which is worse than absent.
    #expect(try StageZeroPick(hit: hit(basis: .shade, n: 0)) == nil)
    #expect(try StageZeroPick(hit: hit(basis: .popular, n: 0)) == nil)
}

@Test func noReasonNamesTheCohortByValue() {
    // GLO-205 and GLO-167: cohorts are named by kind, never by the value.
    // "your shade", never the shade itself.
    for basis in [DiscoverHit.Basis.shade, .taste, .everyone, .popular] {
        let reason = StageZeroPick.reason(for: basis)
        #expect(reason == reason.lowercased())
        #expect(!reason.contains("240"))
        #expect(!reason.contains("combo"))
    }
}

@Test func theStoreDropsUnusableRowsRatherThanFailing() async throws {
    // A feed that is half wander and half evidence still produces a screen.
    let rows = try [
        hit(basis: .shade, n: 9),
        hit(basis: .exploration, n: 0),
        hit(basis: .taste, n: 4)
    ]
    let store = ShelfStageZeroStore { _ in rows.compactMap(StageZeroPick.init(hit:)) }
    let picks = try await store.picks(3)
    #expect(picks.count == 2)
    #expect(picks.allSatisfy { $0.n > 0 })
}
