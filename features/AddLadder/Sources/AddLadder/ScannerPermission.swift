import AVFoundation
import Foundation
#if os(iOS) && !targetEnvironment(macCatalyst)
    import VisionKit
#endif

/// Deciding whether the scanner can run, and telling the two "no"s apart.
///
/// The decision is a pure function of two inputs plus, at most, one question to
/// the user — so it is tested here rather than discovered on a device. Getting
/// it wrong is not subtle from the user's side: a first-time user who has never
/// been asked would be told their camera is off and sent to Settings to fix
/// something that is not broken.
public enum ScannerPermission {
    /// - Parameters:
    ///   - isSupported: whether this hardware has a scanner at all.
    ///   - status: the camera authorization the system already has on record.
    ///   - requestAccess: asks the user. Called only when nobody has asked yet.
    ///
    /// Main-actor isolated so the caller's closure never crosses an isolation
    /// boundary — a permission prompt is a UI event, and under Swift 6's strict
    /// checking a nonisolated version cannot take one without `@Sendable`,
    /// which would push a box into every call site including the tests.
    @MainActor
    public static func resolve(
        isSupported: Bool,
        status: AVAuthorizationStatus,
        requestAccess: () async -> Bool
    ) async -> ScannerAvailability {
        // Hardware first: asking for the camera on a device that cannot scan
        // spends the one permission prompt we get on nothing.
        guard isSupported else { return .unsupportedDevice }

        switch status {
        case .authorized:
            return .ready
        case .notDetermined:
            return await requestAccess() ? .ready : .permissionDenied
        case .denied, .restricted:
            return .permissionDenied
        @unknown default:
            // A status we do not recognise is not permission to use a camera.
            return .permissionDenied
        }
    }
}

public extension ScannerPermission {
    /// The live answer.
    ///
    /// VisionKit exists on macOS but `DataScannerViewController` does not — it
    /// is a UIViewController, and unavailable on Catalyst besides. So the guard
    /// is on the platform rather than the module, and everywhere else honestly
    /// reports hardware that cannot scan.
    @MainActor
    static func current() async -> ScannerAvailability {
        #if os(iOS) && !targetEnvironment(macCatalyst)
            await resolve(
                isSupported: DataScannerViewController.isSupported,
                status: AVCaptureDevice.authorizationStatus(for: .video),
                requestAccess: { await AVCaptureDevice.requestAccess(for: .video) }
            )
        #else
            .unsupportedDevice
        #endif
    }
}
