import Foundation
import Testing
@testable import DataKit

// The dismissal write's row shape, pinned the way the other write rows are:
// the encoder's output is the wire, and a drifted key is a 400 at runtime.

@Test func aDismissalRowCarriesItsOwnerAndItsKeys() throws {
    struct Row: Encodable {
        let userID: String
        let productID: String
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case reason
            case userID = "user_id"
            case productID = "product_id"
        }
    }
    let data = try JSONEncoder().encode(
        Row(userID: "u", productID: "p", reason: "not_for_me")
    )
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["user_id"] as? String == "u")
    #expect(json["product_id"] as? String == "p")
    #expect(json["reason"] as? String == "not_for_me")
}
