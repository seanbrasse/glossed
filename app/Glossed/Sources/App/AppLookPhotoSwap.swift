import DataKit
import Foundation
import Media

// The look-photo swap pipeline (0054's ruling), composed here for
// AppProfilePhoto's reason: Media prepares, storage_presign signs the look
// namespace, DataKit swaps the row's key — three layers no feature may join.

enum LookPhotoSwap {
    private struct PresignRequest: Encodable {
        let lookID: String
        let position: Int
        let contentType: String
        let contentLength: Int

        enum CodingKeys: String, CodingKey {
            case lookID = "look_id"
            case position
            case contentType = "content_type"
            case contentLength = "content_length"
        }
    }

    private struct PresignPayload: Decodable {
        let url: URL
        let key: String
    }

    /// The pipeline, one photo wide: prepare → presign this look's namespace
    /// at this photo's position → PUT → swap the row's key. The key moves
    /// only AFTER the bytes landed, and the row keeps its id, position and
    /// tags (0054's grant admits nothing else).
    static func pipeline(
        client: GlossedClient, lookID: UUID, photoID: UUID, position: Int
    ) -> @Sendable (Data) async throws -> Void {
        { data in
            let preparer = PhotoPreparer(checker: AlwaysAllowedChecker())
            let prepared = try await preparer.prepare(data)
            let body = try JSONEncoder().encode(PresignRequest(
                lookID: lookID.uuidString.lowercased(),
                position: position,
                contentType: "image/jpeg",
                contentLength: prepared.jpegData.count
            ))
            let raw = try await client.invokeEdgeFunctionForData("storage_presign", jsonBody: body)
            let presign = try JSONDecoder().decode(PresignPayload.self, from: raw)
            try await PresignedUploader().upload(prepared, to: PresignedUpload(url: presign.url))
            try await LooksRepository(client: client).swapPhotoKey(photoID: photoID, to: presign.key)
        }
    }
}
