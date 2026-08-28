import DataKit
import Foundation
import Observation
import Shelf

/// The app's one session, and the data the shell hangs off it.
///
/// Real auth (Sign in with Apple + phone OTP) is GLO-23, deferred by decision:
/// "skip this for now and just wire the app as if it works" (Sean, Aug 28).
/// So DEBUG builds boot by signing in as the seeded user against the local
/// stack — the same env contract and credentials as the `shelf · LIVE` picker
/// state — and release builds refuse honestly until onboarding (GLO-18) and
/// real providers exist. The providers slot into `boot()`; nothing else moves.
@MainActor
@Observable
final class AppSession {
    enum Phase {
        case connecting
        case ready
        case failed(String)
    }

    private(set) var phase = Phase.connecting
    private(set) var client: GlossedClient?
    /// The shelf tab's model. Rebuilt by `reloadShelf()` — the ladder calls
    /// that after landing something, so a new bottle appears without a
    /// relaunch.
    private(set) var shelfModel: ShelfModel?

    func boot() async {
        #if DEBUG
            do {
                var environment = ProcessInfo.processInfo.environment
                if environment["SUPABASE_URL"] == nil {
                    // The simulator's loopback into `supabase start`. Local
                    // only — the hosted URL is deliberately not here to reach.
                    environment["SUPABASE_URL"] = "http://127.0.0.1:54321"
                }
                let config = try GlossedConfig.validated(from: environment)
                let booted = GlossedClient(config: config)
                try await booted.signIn(email: "maya@local.test", password: "password")
                client = booted
                await reloadShelf()
                phase = .ready
            } catch let error as GlossedError {
                phase = .failed("\(error.code.rawValue): \(error.debugDetail ?? error.userMessage)")
            } catch {
                phase = .failed(String(describing: error))
            }
        #else
            // No release sign-in path exists yet, and pretending otherwise
            // would be worse: onboarding is GLO-18, providers are GLO-23.
            phase = .failed("no sign-in path in release builds yet — GLO-18/GLO-23")
        #endif
    }

    /// One read of `user_shelf_items`, rebuilt into a fresh model. Failure
    /// keeps the previous model on screen — a shelf that vanishes because a
    /// refresh failed would read as data loss.
    func reloadShelf() async {
        guard let client else { return }
        let repository = ShelfRepository(client: client)
        guard let rows = try? await repository.shelf() else { return }
        shelfModel = ShelfModel(
            sections: ShelfSection.grouped(from: rows),
            fitStore: .repository(repository)
        )
    }

    /// The fire-and-forget shape the ladder's callback needs.
    func refreshShelf() {
        Task { await reloadShelf() }
    }
}
