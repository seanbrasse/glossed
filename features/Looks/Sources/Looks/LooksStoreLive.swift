import DataKit
import Foundation
import Media

/// What `storage_presign` returns for a look upload. Decoded HERE — DataKit
/// hands function payloads back as opaque bytes by doctrine, and the feature
/// that knows the shape owns the decode (the GLO-93 pattern).
struct PresignPayload: Decodable {
    let url: URL
    let key: String
    let headers: [String: String]?
}

struct PresignRequest: Encodable {
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

public extension LooksStore {
    /// The real pipeline, in the order tech/03 §1 names it: each photo is
    /// prepared on device (screen → strip → bound), presigned, PUT, and only
    /// keys that actually landed reach the draft — a failed upload fails the
    /// save rather than filing a look whose photo does not exist.
    ///
    /// Idempotent end to end: the draft's lookID is minted ONCE per composer
    /// session, so a retry re-lands the same row (0043's primary key), and
    /// re-uploading a photo overwrites its own object rather than leaking a
    /// sibling.
    static func live(
        client: GlossedClient,
        preparer: PhotoPreparer,
        uploader: PresignedUploader = PresignedUploader()
    ) -> LooksStore {
        let repository = LooksRepository(client: client)
        let lookID = UUID()
        return LooksStore(
            save: { caption, photos, spots in
                var uploaded: [LookDraft.Photo] = []
                for photo in photos.sorted(by: { $0.position < $1.position }) {
                    let prepared = try await preparer.prepare(photo.localData)
                    // The function discriminates namespace by WHICH id is
                    // present, and the signature commits to type + byte count
                    // — so the length is the prepared jpeg's, after strip and
                    // re-encode, never the picked original's.
                    let body = try JSONEncoder().encode(PresignRequest(
                        lookID: lookID.uuidString.lowercased(),
                        position: photo.position,
                        contentType: "image/jpeg",
                        contentLength: prepared.jpegData.count
                    ))
                    let raw = try await client.invokeEdgeFunctionForData("storage_presign", jsonBody: body)
                    let presign = try JSONDecoder().decode(PresignPayload.self, from: raw)
                    try await uploader.upload(prepared, to: PresignedUpload(
                        url: presign.url, headers: presign.headers ?? [:]
                    ))
                    // The composer's photo id IS the draft's photo id — the
                    // board's spots reference it, so inventing a second id
                    // here would orphan every tag at the join.
                    uploaded.append(.init(id: photo.id, r2Key: presign.key, position: photo.position))
                }
                return try await repository.saveDraft(LookDraft(
                    caption: caption.isEmpty ? nil : caption,
                    photos: uploaded,
                    spots: spots.map { spot in
                        LookDraft.Spot(
                            id: spot.id,
                            photoID: spot.photoID,
                            x: spot.point.x,
                            y: spot.point.y,
                            products: spot.products.enumerated().map { index, product in
                                LookDraft.SpotProduct(variantID: product.variantID, position: index)
                            }
                        )
                    },
                    lookID: lookID
                ))
            },
            searchShelf: { _ in
                // The shelf search wiring rides the tag-picker sheet slice —
                // an empty answer here is honest: nothing offers the picker
                // yet, and a stubbed non-answer must not pretend otherwise.
                []
            }
        )
    }
}
