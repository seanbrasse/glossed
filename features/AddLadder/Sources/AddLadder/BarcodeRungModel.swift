import DataKit
import Foundation
import Observation

/// Whether the camera can scan, and if not, why not.
///
/// Injected rather than read from `DataScannerViewController` here: the split
/// between "this device cannot" and "you said no" is the whole point, and both
/// need to be reachable in a test on a machine with neither.
public enum ScannerAvailability: Equatable, Sendable {
    /// Hardware and permission are both there.
    case ready
    /// No scanner on this device. Nothing the user can do, so do not ask.
    case unsupportedDevice
    /// Camera access refused or restricted. Recoverable, and the only case
    /// where pointing at Settings is anything but noise.
    case permissionDenied

    var explanation: String {
        switch self {
        case .ready: ""
        case .unsupportedDevice: "this phone can't scan — the other ways still work"
        case .permissionDenied: "camera's off for glossed — turn it on in settings, or keep going"
        }
    }
}

/// The barcode rung's state.
///
/// The rung the spec pushes as the common path, which makes its failures the
/// ones most worth getting right: an unreadable code, a missing camera and a
/// refused permission are three different problems, and none of them is allowed
/// to end the trip.
@MainActor
@Observable
public final class BarcodeRungModel {
    public private(set) var ladder: Ladder
    public private(set) var availability: ScannerAvailability
    public private(set) var isResolving = false
    public private(set) var failure: GlossedError?
    /// What to tell the user right now. Nil when the scanner is just scanning.
    public private(set) var message: String?

    /// The code currently being resolved, or already resolved. The recognized-
    /// items stream re-reports the same barcode many times a second, so without
    /// this every frame would fire another lookup.
    private var handled: String?
    private let rung: BarcodeRung

    public init(catalog: any VariantLookup, availability: ScannerAvailability = .ready) {
        rung = BarcodeRung(catalog: catalog)
        self.availability = availability
        ladder = Ladder(entry: .barcode)
        message = availability == .ready ? nil : availability.explanation
    }

    public var isScanning: Bool {
        availability == .ready && !ladder.isResolved
    }

    /// Always present, always advancing, and it says what it will do — which
    /// matters most here, because a user whose camera is off needs the way
    /// forward to be the obvious thing on screen rather than a consolation.
    ///
    /// One label, which is what the frame writes. It said "no camera" when the
    /// camera was unavailable, and that fact now has a better place to live:
    /// the card above states it at display size, where someone looking for the
    /// reason will actually find it. Repeating it on the row cost the row its
    /// destination, and the destination is the part that is a decision.
    public let escapePrompt = "no barcode — show me near matches"

    /// A payload from the scanner. Safe to call on every frame.
    public func scanned(_ payload: String) async {
        // The guard and the assignment must stay together, above the first
        // `await`. This type is main-actor isolated and Swift will not suspend
        // it between two synchronous statements, which is the whole reason one
        // label held for thirty frames is one lookup. Insert an `await` between
        // these two lines and the dedupe silently stops working, with nothing
        // from the compiler to say so.
        guard !ladder.isResolved, handled != payload else { return }
        handled = payload
        isResolving = true
        failure = nil
        defer { isResolving = false }

        do {
            switch try await rung.resolve(scanned: payload) {
            case let .matched(variant):
                message = nil
                ladder.matched(variantID: variant.id)
            case let .unknownCode(gtin):
                message = "not in the catalog yet — noted"
                ladder.scanMissed(gtin: gtin)
            case .misread:
                // Not a miss and not a match, so nothing is recorded and the
                // ladder does not move. Let the same code be tried again.
                message = "couldn't read that — hold it steadier"
                handled = nil
            }
        } catch {
            // A lookup that failed is not an answer about the catalog. Saying
            // "not in the catalog yet" here would send someone off to create a
            // product we already stock.
            failure = error
            message = error.userMessage
            handled = nil
        }
    }

    public func noneOfThese() {
        ladder.noneOfThese()
    }

    /// The camera's answer, once the system has given one.
    ///
    /// Availability is not fixed for the life of the screen: the first check
    /// may have to ask the user, and someone can flip the switch in Settings
    /// and come back. Re-reading it is why this is a method rather than a
    /// constructor argument.
    public func availabilityChanged(to new: ScannerAvailability) {
        availability = new
        if !hasSomethingToSayAboutACode {
            message = new == .ready ? nil : new.explanation
        }
    }

    /// Whether anything more specific than the camera's status is on screen.
    ///
    /// A message about a code we just read is both more specific and more
    /// recent than one about the camera, so it wins — the rung re-checks
    /// availability whenever it reappears, and without this "not in the catalog
    /// yet — noted" would vanish exactly as the user looks up to read it.
    /// Named once here because it is three independently-mutated fields
    /// standing in for one idea, and a fourth would otherwise be easy to forget.
    private var hasSomethingToSayAboutACode: Bool {
        isResolving || failure != nil || handled != nil
    }
}
