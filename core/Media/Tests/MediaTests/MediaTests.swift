import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Media

// MARK: - fixtures

/// A real JPEG with real metadata, built the way a camera would: pixels plus
/// EXIF, GPS and TIFF dictionaries. The strip test only means something if
/// the input verifiably HAS what the output must verifiably lack.
private struct FixtureFailed: Error {}

private func jpegWithLocation(width: Int = 3000, height: Int = 2000) throws -> Data {
    var pixels = [UInt8](repeating: 180, count: width * height * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        pixels[index] = UInt8((index / 4) % 255)
    }
    guard let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ), let image = context.makeImage() else { throw FixtureFailed() }

    let metadata: [CFString: Any] = [
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 40.7128,
            kCGImagePropertyGPSLongitude: 74.0060,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitudeRef: "W"
        ],
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: "2026:08:30 01:00:00",
            kCGImagePropertyExifLensModel: "test lens 26mm"
        ],
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFModel: "TestPhone 99"
        ]
    ]
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil
    ) else { throw FixtureFailed() }
    CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
    CGImageDestinationFinalize(destination)
    return output as Data
}

private func properties(of data: Data) throws -> [CFString: Any] {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { throw FixtureFailed() }
    return props
}

// MARK: - the strip

@Test func theFixtureReallyCarriesLocationOrTheStripTestIsTheater() throws {
    let props = try properties(of: jpegWithLocation())
    #expect(props[kCGImagePropertyGPSDictionary] != nil)
    #expect(props[kCGImagePropertyExifDictionary] != nil)
    #expect(props[kCGImagePropertyTIFFDictionary] != nil)
}

@Test func preparedPhotosCarryNoGPSNoCaptureTimeNoDeviceModel() async throws {
    let preparer = PhotoPreparer(checker: AlwaysAllowedChecker())
    let prepared = try await preparer.prepare(jpegWithLocation())
    let props = try properties(of: prepared.jpegData)

    #expect(props[kCGImagePropertyGPSDictionary] == nil, "location never leaves the device")
    let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
    #expect(exif?[kCGImagePropertyExifDateTimeOriginal] == nil, "no capture time")
    #expect(exif?[kCGImagePropertyExifLensModel] == nil, "no lens")
    let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    #expect(tiff?[kCGImagePropertyTIFFModel] == nil, "no device model")
}

@Test func preparedPhotosAreBoundedToTheMaxEdge() async throws {
    let preparer = PhotoPreparer(checker: AlwaysAllowedChecker())
    let prepared = try await preparer.prepare(jpegWithLocation(width: 4000, height: 3000))
    #expect(max(prepared.pixelWidth, prepared.pixelHeight) <= PhotoPreparer.maxPixelEdge)
    #expect(prepared.pixelWidth > 0 && prepared.pixelHeight > 0)
}

@Test func garbageBytesAreUndecodableNotACrash() async {
    let preparer = PhotoPreparer(checker: AlwaysAllowedChecker())
    await #expect(throws: PhotoPreparationError.undecodable) {
        _ = try await preparer.prepare(Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }
}

// MARK: - the content check fails closed

private struct RefusingChecker: SensitiveContentChecking {
    func isAllowed(_: Data) async throws -> Bool {
        false
    }
}

private struct BrokenChecker: SensitiveContentChecking {
    struct Unavailable: Error {}
    func isAllowed(_: Data) async throws -> Bool {
        throw Unavailable()
    }
}

@Test func aRefusedPhotoNeverReachesPreparation() async throws {
    let preparer = PhotoPreparer(checker: RefusingChecker())
    let data = try jpegWithLocation()
    await #expect(throws: PhotoPreparationError.blockedByContentCheck) {
        _ = try await preparer.prepare(data)
    }
}

@Test func aBrokenCheckerFailsClosedNotOpen() async throws {
    // A screening step that fails open is not a screening step.
    let preparer = PhotoPreparer(checker: BrokenChecker())
    let data = try jpegWithLocation()
    await #expect(throws: PhotoPreparationError.blockedByContentCheck) {
        _ = try await preparer.prepare(data)
    }
}

// MARK: - the uploader

private class RecordingProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var lastMethod: String?
    nonisolated(unsafe) static var lastContentType: String?
    nonisolated(unsafe) static var lastHeader: String?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastMethod = request.httpMethod
        Self.lastContentType = request.value(forHTTPHeaderField: "Content-Type")
        Self.lastHeader = request.value(forHTTPHeaderField: "x-presigned-token")
        if let url = request.url, let response = HTTPURLResponse(
            url: url, statusCode: Self.status, httpVersion: nil, headerFields: nil
        ) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func mockedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RecordingProtocol.self]
    return URLSession(configuration: config)
}

/// Serialized: the two tests share RecordingProtocol's static state, and
/// parallel execution let one test's status leak into the other's request.
@Suite(.serialized)
struct UploaderTests {
    @Test func uploadPUTsJPEGBytesWithThePresignedHeaders() async throws {
        RecordingProtocol.status = 200
        let uploader = PresignedUploader(session: mockedSession())
        let photo = PreparedPhoto(jpegData: Data([1, 2, 3]), pixelWidth: 1, pixelHeight: 1)
        try await uploader.upload(photo, to: PresignedUpload(
            url: #require(URL(string: "https://storage.example/looks/abc")),
            headers: ["x-presigned-token": "tok"]
        ))
        #expect(RecordingProtocol.lastMethod == "PUT")
        #expect(RecordingProtocol.lastContentType == "image/jpeg")
        #expect(RecordingProtocol.lastHeader == "tok")
    }

    @Test func aRejectionSurfacesItsStatusRatherThanPassingSilently() async throws {
        RecordingProtocol.status = 403
        let uploader = PresignedUploader(session: mockedSession())
        let photo = PreparedPhoto(jpegData: Data([1]), pixelWidth: 1, pixelHeight: 1)
        await #expect(throws: UploadError.rejected(status: 403)) {
            try await uploader.upload(photo, to: PresignedUpload(
                url: #require(URL(string: "https://storage.example/looks/abc"))
            ))
        }
    }
}
