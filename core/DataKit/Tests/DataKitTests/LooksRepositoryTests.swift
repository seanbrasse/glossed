import Foundation
import Testing
@testable import DataKit

// Pure rules the looks repository encodes; the policies themselves are proven
// by pgTAP (looks.test.sql), which is the actual security boundary.

@Test func aDraftMintsItsOwnPrimaryKeyAndKeepsACallerSuppliedOne() {
    let one = LookDraft(caption: nil, photos: [], tags: [])
    let two = LookDraft(caption: nil, photos: [], tags: [])
    #expect(one.lookID != two.lookID)
    // …and a retry of the SAME draft is the same row, not a duplicate.
    let fixed = UUID()
    #expect(LookDraft(caption: nil, photos: [], tags: [], lookID: fixed).lookID == fixed)
}

@Test func rowEncodingsMatchTheMigrationsColumns() throws {
    // 0043's column names, spelled out — drift comes back as a server error
    // at best and a silently-ignored key at worst.
    let look = LooksRepository.LookRow(id: UUID(), userID: UUID(), caption: "c")
    let lookKeys = try keys(of: look)
    #expect(lookKeys == ["caption", "id", "user_id"])

    let photo = LooksRepository.PhotoRow(lookID: UUID(), r2Key: "k", position: 0)
    #expect(try keys(of: photo) == ["look_id", "position", "r2_key"])

    let tag = LooksRepository.TagRow(lookID: UUID(), variantID: UUID(), x: 0.5, y: 0.5)
    #expect(try keys(of: tag) == ["look_id", "variant_id", "x", "y"])
}

private func keys(of value: some Encodable) throws -> [String] {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return (object ?? [:]).keys.sorted()
}
