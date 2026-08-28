import Foundation
import Testing
@testable import DataKit

// The RPC payload is a jsonb contract with the database. Its key names are the
// contract, so they are asserted here rather than discovered at runtime.

private func encodedJSON(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}

@Test func faceOffRecordEncodesTheDatabaseColumnNames() throws {
    let record = FaceOffRecord(categoryID: UUID(), winnerItemID: UUID(), loserItemID: UUID())
    let json = try encodedJSON(record)
    #expect(Set(json.keys) == ["category_id", "scope_key", "winner_item_id", "loser_item_id", "skipped", "client_id"])
}

@Test func rankPositionEncodesTheDatabaseColumnNames() throws {
    let position = RankPosition(categoryID: UUID(), userItemID: UUID(), position: 1)
    let json = try encodedJSON(position)
    #expect(Set(json.keys) == ["category_id", "scope_key", "user_item_id", "position"])
}

@Test func sessionParamsUseThePrefixedRPCArgumentNames() throws {
    let params = FaceOffSessionParams(faceOffs: [], positions: [])
    let json = try encodedJSON(params)
    #expect(Set(json.keys) == ["p_face_offs", "p_positions"])
}

@Test func comparisonsDefaultToScopedAndCounted() {
    let record = FaceOffRecord(categoryID: UUID(), winnerItemID: UUID(), loserItemID: UUID())
    #expect(record.scopeKey == "default")
    // A comparison counts unless it was explicitly skipped.
    #expect(record.skipped == false)
}

@Test func eachComparisonCarriesItsOwnIdempotencyKey() {
    let category = UUID()
    let winner = UUID()
    let loser = UUID()
    let first = FaceOffRecord(categoryID: category, winnerItemID: winner, loserItemID: loser)
    let second = FaceOffRecord(categoryID: category, winnerItemID: winner, loserItemID: loser)
    // Two genuine answers to the same pairing are two comparisons…
    #expect(first.clientID != second.clientID)
    // …but replaying one is not: the key travels with the record.
    #expect(first.clientID == FaceOffRecord(
        categoryID: category, winnerItemID: winner, loserItemID: loser, clientID: first.clientID
    ).clientID)
}

@Test func payoffWithoutEvidenceMakesNoClaim() {
    let empty = PayoffEvidence(exactShadeCount: 0, withFitCount: 0, evidenceBacked: false)
    #expect(empty.evidenceBacked == false)
    // The screen must fall back to neutral copy — never "0 people wear your shade".
    #expect(empty.exactShadeCount == 0)
}

@Test func payoffDecodesTheRPCColumnNames() throws {
    let raw = Data(#"{"n_exact_shade":12,"n_with_fit":9,"evidence_backed":true}"#.utf8)
    let evidence = try JSONDecoder().decode(PayoffEvidence.self, from: raw)
    #expect(evidence.exactShadeCount == 12)
    #expect(evidence.withFitCount == 9)
    #expect(evidence.evidenceBacked)
}
