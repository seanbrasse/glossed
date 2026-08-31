import DataKit
import Foundation
import Media
import Profile

// The pfp pipeline (GLO-272), composed here because it crosses three layers
// no feature may join: Media prepares, storage_presign signs (#452/#454),
// DataKit stores the key (#455). The same shape as `LooksStoreLive`'s upload
// half, one photo wide.

extension ProfilePhotoStore {
    private struct WritePresign: Decodable {
        let url: URL
        let key: String
    }

    private struct WriteRequest: Encodable {
        let profilePhoto = true
        let contentType: String
        let contentLength: Int

        enum CodingKeys: String, CodingKey {
            case profilePhoto = "profile_photo"
            case contentType = "content_type"
            case contentLength = "content_length"
        }
    }

    private struct ReadPresign: Decodable {
        let url: URL?
    }

    /// The live pipeline: prepare (screen → strip → bound, the tech/03 §1
    /// order) → presign → PUT → store the key. The key goes to the row only
    /// AFTER the bytes landed, so `photo_r2_key` never points at an object
    /// that does not exist.
    static func live(client: GlossedClient) -> ProfilePhotoStore {
        let profile = ProfileRepository(client: client)
        // The same visibly-chosen checker as the look composer, and the same
        // bound on what that means: this photo reaches the owner's own
        // account and stops there — no read path shows a pfp to anyone else
        // yet, and THAT path owes the moderation story (GLO-26's family).
        let preparer = PhotoPreparer(checker: AlwaysAllowedChecker())
        let uploader = PresignedUploader()
        return ProfilePhotoStore(
            currentURL: {
                guard let body = try? JSONEncoder().encode(["profile_photo_read": true]),
                      let raw = try? await client.invokeEdgeFunctionForData(
                          "storage_presign", jsonBody: body
                      ),
                      let payload = try? JSONDecoder().decode(ReadPresign.self, from: raw)
                else {
                    // Nil is the seeded initial — chrome degrades, headers
                    // do not break.
                    return nil
                }
                return payload.url
            },
            upload: { data in
                let prepared = try await preparer.prepare(data)
                let body = try JSONEncoder().encode(WriteRequest(
                    contentType: "image/jpeg", contentLength: prepared.jpegData.count
                ))
                let raw = try await client.invokeEdgeFunctionForData("storage_presign", jsonBody: body)
                let presign = try JSONDecoder().decode(WritePresign.self, from: raw)
                try await uploader.upload(prepared, to: PresignedUpload(url: presign.url))
                try await profile.setPhotoKey(presign.key)
            }
        )
    }
}
