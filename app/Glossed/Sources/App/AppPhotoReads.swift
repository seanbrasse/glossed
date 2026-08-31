import DataKit
import Foundation

/// Signed GET URLs for look photos, batched (GLO-272's read path).
///
/// Lives in the APP layer because two features need it — the profile's tiles
/// preview a first photo, the post host renders a carousel — and features
/// never import features. Each hands this a photo-id list through its own
/// seam; the payload decode happens here for the same reason
/// `LooksStoreLive` decodes its upload payload itself: DataKit stays
/// payload-ignorant (GLO-93).
///
/// **Absence is an answer.** The function returns URLs only for photos RLS
/// admitted (per-item visibility, 0053), so a missing id renders as its
/// placeholder — never an error, and never a retry loop against a photo the
/// viewer may not see.
struct LookPhotoURLResolver: Sendable {
    private let client: GlossedClient

    init(client: GlossedClient) {
        self.client = client
    }

    private struct Request: Encodable {
        let lookPhotoIDs: [String]

        enum CodingKeys: String, CodingKey {
            case lookPhotoIDs = "look_photo_ids"
        }
    }

    private struct Payload: Decodable {
        let urls: [String: URL]
    }

    /// One call per batch — sized to the function's own cap. More ids than
    /// that is paged here rather than rejected there, so a heavy profile
    /// still resolves completely.
    private static let batchMax = 60

    func resolve(_ photoIDs: [UUID]) async -> [UUID: URL] {
        guard !photoIDs.isEmpty else { return [:] }
        var result: [UUID: URL] = [:]
        for start in stride(from: 0, to: photoIDs.count, by: Self.batchMax) {
            let slice = Array(photoIDs[start ..< min(start + Self.batchMax, photoIDs.count)])
            guard
                let body = try? JSONEncoder().encode(
                    Request(lookPhotoIDs: slice.map { $0.uuidString.lowercased() })
                ),
                let raw = try? await client.invokeEdgeFunctionForData("storage_presign", jsonBody: body),
                let payload = try? JSONDecoder().decode(Payload.self, from: raw)
            else {
                // A failed batch degrades to placeholders for ITS photos and
                // keeps going — a preview is chrome, and chrome must not
                // take a screen down. The post view's `.unavailable` copy is
                // the named failure.
                continue
            }
            for (id, url) in payload.urls {
                if let uuid = UUID(uuidString: id) {
                    result[uuid] = url
                }
            }
        }
        return result
    }
}
