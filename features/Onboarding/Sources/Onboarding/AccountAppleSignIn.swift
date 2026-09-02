import AuthenticationServices
import DataKit
import Foundation

// GLO-23's Apple walk, in its own file because `AccountModel.swift` sits at
// SwiftLint's 300-line ceiling — the same extract-rather-than-accrete move
// `OnbAccountStages` and `AppShellTabs` made.

public extension AccountModel {
    /// Runs Apple's sheet, hands the token to the server, and only then moves
    /// the walk on.
    ///
    /// **The ordering is the point.** The old `chooseApple()` advanced the
    /// stage the instant the button was pressed, which was right while there
    /// was no auth to do and wrong the moment there is: a stage that moves
    /// before the sign-in lands tells the user they are in when they may not
    /// be. Nothing here advances until `store.signInWithApple` returns.
    ///
    /// **A cancel is not a failure.** Apple reports "the user dismissed the
    /// sheet" as a thrown error, and showing that as *"something went wrong"*
    /// would be the app inventing a problem out of a shrug. It is swallowed,
    /// the walk stays put, and the button is live again.
    ///
    /// With no store wired — previews, the debug picker — this keeps the
    /// pre-GLO-23 behaviour so those doors do not go dark.
    func signInWithApple(onDone: @escaping () -> Void) {
        guard let handoff = store?.signInWithApple else {
            chooseApple()
            onDone()
            return
        }
        guard !isCreating else { return }

        creationError = nil
        isCreating = true
        createTask = Task { [weak self] in
            defer { self?.isCreating = false }
            do {
                try await handoff()
                guard let self else { return }
                // Same Apple ID, same user: "create an account" with an
                // account is a login through the other door. A failed read
                // is treated as "new" — the write is idempotent, and
                // re-asking beats refusing.
                if mode == .signup, await (try? store?.hasProfile()) == true {
                    landAsExistingAccount()
                } else {
                    chooseApple()
                }
                onDone()
            } catch let error as ASAuthorizationError where error.code == .canceled {
                return
            } catch {
                self?.creationError = GlossedError.from(error)
            }
        }
    }
}
