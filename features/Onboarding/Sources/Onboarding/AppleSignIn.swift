import AuthenticationServices
import CryptoKit
import Foundation

#if canImport(UIKit)
    import UIKit
#endif

// Sign in with Apple, native flow (GLO-23). The credential half — everything
// that needs a window and Apple's own framework — lives here rather than in
// DataKit, which only knows how to hand a finished token to the server.
//
// The split is not tidiness. `AuthenticationServices` needs a presentation
// anchor, and the frozen core has no business knowing what a window is.

/// What Apple hands back, reduced to the three facts anything downstream needs.
///
/// `fullName` is optional because **Apple supplies it exactly once** — on the
/// very first authorization for a given App ID, and never again, not even
/// after a reinstall. Treating a later nil as an error would break every
/// returning user; treating it as "not offered this time" is the truth.
public struct AppleIdentity: Sendable, Equatable {
    public let idToken: String
    /// The ORIGINAL nonce, not the hash Apple was given. See `AppleNonce`.
    public let rawNonce: String
    public let fullName: String?

    public init(idToken: String, rawNonce: String, fullName: String?) {
        self.idToken = idToken
        self.rawNonce = rawNonce
        self.fullName = fullName
    }
}

/// The nonce pair, and the one place the hashing direction is written down.
///
/// **Apple gets the hash, the server gets the original.** A random string is
/// generated, its SHA256 goes onto the request, and Apple stamps that hash
/// into the identity token's `nonce` claim. Supabase then hashes whatever it
/// is handed and compares. So sending the hash to both ends makes the server
/// compare `sha256(hash)` against `hash` and reject every attempt — with a
/// signature error that names nothing about nonces. Two values, and only one
/// of them is ever allowed to leave this type.
public enum AppleNonce {
    /// Apple's own sample uses this charset; kept so the value is URL- and
    /// header-safe wherever it travels.
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

    /// `randomElement()` draws from `SystemRandomNumberGenerator`, which Apple
    /// documents as cryptographically secure on its platforms — so this is not
    /// the place a hand-rolled RNG sneaks in.
    public static func random(_ length: Int = 32) -> String {
        String((0 ..< length).compactMap { _ in charset.randomElement() })
    }

    /// Lowercase hex, which is the form Apple's `nonce` claim carries.
    public static func hashed(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public extension AppleIdentity {
    /// Reads an authorization without touching Apple's framework types
    /// anywhere else in the app.
    ///
    /// Returns nil rather than throwing on a shape we did not expect: a
    /// credential that is not an Apple ID credential, or one whose identity
    /// token will not decode as UTF-8. Both are "Apple gave us something we
    /// cannot use", which the caller surfaces as one honest failure instead of
    /// three that mean the same thing.
    init?(authorization: ASAuthorization, rawNonce: String) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else { return nil }

        // `PersonNameComponentsFormatter` rather than "given + family": name
        // order is not universal, and the formatter knows the locale's rule.
        // Empty components format to an empty string, which is not a name —
        // hence the trim-and-nil rather than storing "".
        var name: String?
        if let components = credential.fullName {
            let formatted = PersonNameComponentsFormatter().string(from: components)
            let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
            name = trimmed.isEmpty ? nil : trimmed
        }

        self.init(idToken: idToken, rawNonce: rawNonce, fullName: name)
    }
}

/// Runs Apple's sheet and resolves to an identity, or throws.
///
/// A class rather than a struct because `ASAuthorizationController` demands a
/// delegate and holds it weakly — the caller has to keep this alive across the
/// await, which is exactly what a stored model property does.
@MainActor
public final class AppleSignInController: NSObject {
    /// Apple's own cancel code, surfaced so a caller can tell "the user
    /// changed their mind" from "this is broken" — a cancel is not an error
    /// worth showing anybody.
    public static let canceledCode = ASAuthorizationError.canceled.rawValue

    private var continuation: CheckedContinuation<AppleIdentity, any Error>?
    private var rawNonce = ""

    override public init() {
        super.init()
    }

    public func signIn() async throws -> AppleIdentity {
        let raw = AppleNonce.random()
        rawNonce = raw

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.hashed(raw)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    /// Resumes exactly once. Apple calls back on one path or the other, but a
    /// continuation resumed twice is a crash rather than a bug report, so the
    /// stored reference is cleared as it is taken.
    private func finish(_ result: Result<AppleIdentity, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

extension AppleSignInController: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let identity = AppleIdentity(authorization: authorization, rawNonce: rawNonce) else {
            finish(.failure(ASAuthorizationError(.invalidResponse)))
            return
        }
        finish(.success(identity))
    }

    public func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        finish(.failure(error))
    }
}

extension AppleSignInController: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }
            return window ?? ASPresentationAnchor()
        #else
            // macOS builds exist so the packages typecheck in CI; nothing
            // drives this path there.
            return ASPresentationAnchor()
        #endif
    }
}
