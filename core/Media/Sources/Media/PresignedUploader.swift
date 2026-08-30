import Foundation

/// What a presign Edge Function hands back, as this package needs it. The
/// FEATURE decodes the function's payload and builds one of these — DataKit
/// stays payload-ignorant (its own doctrine), and Media stays supabase-
/// ignorant: a URL, a method's worth of headers, nothing else.
public struct PresignedUpload: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

public enum UploadError: Error, Equatable {
    /// The server said no. The status is kept for the log line — the user
    /// copy never shows a number.
    case rejected(status: Int)
    case transport
}

/// PUTs prepared bytes to a presigned URL. Deliberately dumb: no retries (the
/// caller owns retry UX — a failure must surface, not silently loop), no
/// supabase types, no session. The URL IS the authorization.
public struct PresignedUploader: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func upload(_ photo: PreparedPhoto, to presigned: PresignedUpload) async throws {
        var request = URLRequest(url: presigned.url)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        for (field, value) in presigned.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        do {
            let (_, response) = try await session.upload(for: request, from: photo.jpegData)
            guard let http = response as? HTTPURLResponse else {
                throw UploadError.transport
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw UploadError.rejected(status: http.statusCode)
            }
        } catch let error as UploadError {
            throw error
        } catch {
            throw UploadError.transport
        }
    }
}
