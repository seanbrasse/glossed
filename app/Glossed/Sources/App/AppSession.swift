import DataKit
import Discover
import Foundation
import Observation
import Shelf
import Tracking

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
    /// Where catalog cutouts are served from: the stack's public storage
    /// bucket. Composed from config, so the storage move (local → R2) is an
    /// env change here and nowhere else (GLO-74).
    /// Internal, not private: the shell hands it to the ladder as the
    /// catalog-image environment (GLO-83) — same base the shelf composes with.
    private(set) var imageBase: URL?
    /// The shelf tab's model. Rebuilt by `reloadShelf()` — the ladder calls
    /// that after landing something, so a new bottle appears without a
    /// relaunch.
    private(set) var shelfModel: ShelfModel?
    /// The discover tab's model (GLO-20). Rebuilt with the shelf: logging
    /// something changes what should be picked, and the two going stale
    /// together is the cheap correct behavior.
    private(set) var discoverModel: DiscoverModel?
    /// The one Tracker (GLO-80): owned here, injected into features the way
    /// repositories are. Events queue in memory and post to `track_ingest`
    /// in batches; `flush()` fires on scene transitions from the shell.
    private(set) var tracker: Tracker?

    /// Clears everything a signed-in session held (GLO-213).
    ///
    /// Deliberately does NOT call `boot()`. The debug build signs in as
    /// maya automatically, so re-booting would put the user straight back
    /// where they were and make sign out look broken — a tap that appears to
    /// do nothing is worse than no button.
    func signedOut() {
        client = nil
        tracker = nil
        shelfModel = nil
        imageBase = nil
    }

    func boot() async {
        #if DEBUG
            do {
                var environment = ProcessInfo.processInfo.environment
                // Three sources, most specific first: the launch environment,
                // then the bundle, then the simulator's loopback.
                //
                // **The bundle rung exists because a phone has no launch
                // environment.** `make run` hands the simulator both values
                // via `SIMCTL_CHILD_*`, which works precisely because we are
                // the ones launching it. Tapping an icon on a device launches
                // with nothing, and `SUPABASE_PUBLISHABLE_KEY` has no default
                // at all — so a device build read only from the environment
                // would boot once from our `devicectl` launch and then say
                // "the app isn't set up correctly" every time thereafter.
                // Reading the bundle makes the installed app self-sufficient.
                for key in ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY"] {
                    guard environment[key] == nil else { continue }
                    let bundleKey = key == "SUPABASE_URL"
                        ? "GlossedSupabaseURL"
                        : "GlossedSupabasePublishableKey"
                    // Bound first so the condition stays on one line: a wrapped
                    // two-clause `if let` puts swiftformat (brace on its own
                    // line) and swiftlint's `opening_brace` (same line) in
                    // direct conflict, and there is no spelling of it both
                    // accept.
                    let baked = Bundle.main.object(forInfoDictionaryKey: bundleKey) as? String
                    if let baked, !baked.isEmpty {
                        environment[key] = baked
                    }
                }
                if environment["SUPABASE_URL"] == nil {
                    // The simulator's loopback into `supabase start`. Local
                    // only — the hosted URL is deliberately not here to reach,
                    // and it is loopback rather than the Mac's LAN name
                    // because a simulator shares the Mac's network stack.
                    environment["SUPABASE_URL"] = "http://127.0.0.1:54321"
                }
                let config = try GlossedConfig.validated(from: environment)
                let booted = GlossedClient(config: config)
                try await booted.signIn(email: "maya@local.test", password: "password")
                // **`signIn` returning is not proof the session can be READ
                // back**, and the difference is not academic — it cost a
                // session. `supabase-swift` persists the session to the
                // Keychain, and an UNSIGNED build has no keychain access, so
                // the sign-in succeeded and the very next `auth.session`
                // threw. Every live read came back `notAuthenticated`,
                // `reloadShelf()` swallowed it on its `try?`, and three built
                // tabs rendered their "not built yet" placeholder over a
                // working app.
                //
                // Reproduced by `codesign -d --entitlements`: an app built
                // with `CODE_SIGNING_ALLOWED=NO` — CI's flag, and the one a
                // reader copies out of `ci.yml` — is not signed at all. That
                // flag is correct for CI, which only ever builds. It is wrong
                // for anything you intend to launch.
                //
                // So `.ready` now means "a read works", not "a request
                // returned". Failing here is loud and names the cause;
                // failing later was silent and named the wrong ticket.
                _ = try await booted.requireUserID()
                client = booted
                tracker = Tracker(poster: TrackIngestPoster(client: booted))
                imageBase = config.supabaseURL.appending(path: "storage/v1/object/public/catalog")
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
        discoverModel = DiscoverModel(
            store: .repository(
                AggregatesRepository(client: client),
                taste: TasteRepository(client: client),
                // GLO-260. `DiscoverStore.categories` stays nil without this,
                // so the category eyebrow merged in #388 rendered nothing —
                // a correct, tested, invisible feature waiting on one
                // argument. `catalog` is optional precisely so the app layer
                // could fill it in its own PR; this is that PR.
                catalog: CatalogRepository(client: client)
            ),
            imageBase: imageBase,
            tracker: tracker
        )
        shelfModel = ShelfModel(
            sections: ShelfSection.grouped(from: rows, imageBase: imageBase),
            fitStore: .repository(repository),
            // GLO-87: "would you buy it again?" reads and writes
            // `user_items.like_state` — what you WOULD, beside the status's
            // record of what you DID.
            likeStore: .repository(repository),
            lifecycle: .repository(repository),
            // GLO-16: the chip editor's five calls are all real now (#192),
            // so the sheet writes to `item_chips` and the note column rather
            // than stopping at the seam.
            chipStore: .repository(shelf: repository, catalog: CatalogRepository(client: client)),
            tracker: tracker,
            onShelfChanged: { [weak self] in self?.refreshShelf() }
        )
    }

    /// The fire-and-forget shape the ladder's callback needs.
    func refreshShelf() {
        Task { await reloadShelf() }
    }

    /// Tech/06 §2's lifecycle rule: the queue flushes on background and
    /// foreground. Fire-and-forget — a flush must never hold a transition.
    func flushTracker() {
        guard let tracker else { return }
        Task { await tracker.flush() }
    }
}
