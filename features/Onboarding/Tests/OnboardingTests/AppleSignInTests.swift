import AuthenticationServices
import DataKit
import Testing
@testable import Onboarding

// GLO-23's Apple half. The sheet itself cannot run in a test host — Apple
// presents it from the system — which is exactly why `AccountStore`'s seam
// covers the whole round trip: everything below drives the walk with a stub
// and asserts the part that is ours.

@MainActor
@Suite("apple sign-in")
struct AppleSignInTests {
    @Test("the nonce sent to apple is the hash, never the value sent to the server")
    func nonceHashesRatherThanEchoes() {
        let raw = AppleNonce.random()
        let hashed = AppleNonce.hashed(raw)
        #expect(hashed != raw)
        // 32 bytes of SHA256 as lowercase hex.
        #expect(hashed.count == 64)
        #expect(hashed.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        // Stable: the same input must hash the same way twice, or a retry
        // would fail against a token minted a second earlier.
        #expect(AppleNonce.hashed(raw) == hashed)
    }

    @Test("a known vector, so the hash is SHA256 and not merely some digest")
    func hashesWithSHA256() {
        // sha256("abc"), the FIPS 180-4 example.
        #expect(
            AppleNonce.hashed("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("nonces do not repeat")
    func nonceIsRandom() {
        let batch = Set((0 ..< 64).map { _ in AppleNonce.random() })
        #expect(batch.count == 64)
        #expect(AppleNonce.random(16).count == 16)
    }

    @Test("a successful sign-in advances the walk and reports done")
    func successAdvances() async {
        let model = AccountModel(store: AccountStore(signInWithApple: {}, finish: { _ in }))
        var landed = false
        model.signInWithApple { landed = true }
        await model.createTask?.value

        #expect(landed)
        #expect(model.method == .apple)
        #expect(model.stage == .birthday)
        #expect(model.creationError == nil)
        #expect(!model.isCreating)
    }

    @Test("login mode lands rather than asking for a birthday it already skips")
    func loginModeAuthenticates() async {
        let model = AccountModel(
            mode: .login,
            store: AccountStore(signInWithApple: {}, finish: { _ in })
        )
        model.signInWithApple {}
        await model.createTask?.value

        #expect(model.isAuthenticated)
        #expect(model.stage == .method)
    }

    /// The regression this ticket exists to prevent: the walk used to advance
    /// on the tap. A failure that still moved the user forward would tell them
    /// they were signed in when they were not.
    @Test("a failed sign-in surfaces the error and does NOT advance")
    func failureHoldsTheWalk() async {
        struct Boom: Error {}
        let model = AccountModel(store: AccountStore(signInWithApple: { throw Boom() }, finish: { _ in }))
        var landed = false
        model.signInWithApple { landed = true }
        await model.createTask?.value

        #expect(!landed)
        #expect(model.stage == .method)
        #expect(model.method == nil)
        #expect(model.creationError != nil)
        #expect(!model.isCreating)
    }

    /// A cancel is a shrug, not a fault — showing "something went wrong" for
    /// it would be the app inventing a problem.
    @Test("a cancel leaves no error and no movement")
    func cancelIsSilent() async {
        let model = AccountModel(
            store: AccountStore(
                signInWithApple: { throw ASAuthorizationError(.canceled) },
                finish: { _ in }
            )
        )
        var landed = false
        model.signInWithApple { landed = true }
        await model.createTask?.value

        #expect(!landed)
        #expect(model.creationError == nil)
        #expect(model.stage == .method)
        #expect(!model.isCreating)
    }

    /// Previews and the debug picker pass no store; that door must not go dark.
    @Test("with no seam wired the pre-GLO-23 walk still runs")
    func unwiredKeepsTheOldWalk() {
        let model = AccountModel()
        var landed = false
        model.signInWithApple { landed = true }

        #expect(landed)
        #expect(model.stage == .birthday)
    }
}
