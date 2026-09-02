import DataKit
import Foundation

// Lifted out of `AccountModel.swift` when GLO-23's Apple seam took that file
// past SwiftLint's 300-line ceiling — the same extract-rather-than-trim move
// `ShelfModels` and `CollectionsModels` made. `AccountStore` was always a
// separate type; it only ever shared a file.

/// The seams the app fills: nothing here knows transports. `finish` is the
/// batch profile write (dev session today; the real auth handoff is
/// GLO-23's, and it slots in without changing this shape).
public struct AccountStore: Sendable {
    public var sendCode: @Sendable (_ phone: String) async throws -> Void
    public var verifyCode: @Sendable (_ phone: String, _ code: String) async throws -> Void
    /// GLO-23's Apple half: the sheet AND the server call, as one seam.
    ///
    /// **It takes nothing and returns nothing on purpose.** An earlier shape
    /// had the model run `AppleSignInController` itself and hand the identity
    /// out, which put a real `ASAuthorizationController` inside a method no
    /// test can drive — Apple's sheet cannot be presented in a test host. With
    /// the whole round trip behind one closure the model is exercisable with a
    /// stub, and the composition sits in the app layer where every other
    /// crossing already lives.
    ///
    /// **Optional rather than a no-op default**, because the two states differ:
    /// `sendCode` stubbed out still advances a walk the user can finish,
    /// whereas an Apple button that silently signs nobody in is the
    /// dead-affordance defect (GLO-151). Nil means "not wired".
    public var signInWithApple: (@Sendable () async throws -> Void)?
    /// Does the account that just signed in already have a profile? Asked
    /// right after Apple answers on the SIGNUP path (Sean, Sep 2: *"if a user
    /// already has an account, they can skip entering their birthday"*).
    /// Apple returns the same user for the same Apple ID, so "create an
    /// account" with an account is a login that came in the other door —
    /// and login asks nothing. Default false: a store without the seam
    /// treats everyone as new, which is what every fixture expects.
    public var hasProfile: @Sendable () async throws -> Bool
    public var finish: @Sendable (_ draft: ProfileDraft) async throws -> Void

    public init(
        sendCode: @escaping @Sendable (String) async throws -> Void = { _ in },
        verifyCode: @escaping @Sendable (String, String) async throws -> Void = { _, _ in },
        signInWithApple: (@Sendable () async throws -> Void)? = nil,
        hasProfile: @escaping @Sendable () async throws -> Bool = { false },
        finish: @escaping @Sendable (ProfileDraft) async throws -> Void
    ) {
        self.sendCode = sendCode
        self.verifyCode = verifyCode
        self.signInWithApple = signInWithApple
        self.hasProfile = hasProfile
        self.finish = finish
    }

    /// The live write: the quiz's prior lands through the repository the
    /// DataKit opening added.
    public static func repository(
        _ profiles: ProfileRepository,
        signInWithApple: (@Sendable () async throws -> Void)? = nil
    ) -> AccountStore {
        AccountStore(
            signInWithApple: signInWithApple,
            // `profiles.own()` is the same fact `AppSession.needsOnboarding`
            // reads — a row exists once the account step has written one.
            hasProfile: { try await profiles.own() != nil },
            finish: { try await profiles.saveProfile($0) }
        )
    }
}
