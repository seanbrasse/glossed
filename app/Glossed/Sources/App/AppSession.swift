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
    /// **This account has never answered the quiz, so FLOW 1 is what it gets.**
    ///
    /// The signal is `profiles.own() == nil`, which is the row onboarding's own
    /// account step writes — so the trigger and the thing that clears it are the
    /// same fact, and no separate "seen onboarding" flag can drift from it.
    ///
    /// Real auth is GLO-23 and the DEBUG shell signs in as a seeded user who
    /// already has a profile, so this is false in normal drives. Set
    /// `GLOSSED_ONBOARDING=1` to see the flow anyway — Sean, Aug 31: *"just
    /// ignore auth for now, we will have the flows for before and after and I
    /// will wire it in later."* That is what "before" means here, and when real
    /// sign-up lands a genuinely new account gets FLOW 1 with nothing further
    /// to wire.
    private(set) var needsOnboarding = false
    /// How many things the shelf holds, for `OnbBuildView`'s progress line.
    /// Counted from the same read that builds the model rather than reached for
    /// through it — the count is the session's, not the screen's.
    private(set) var shelfItemCount = 0
    /// brand · product · shade → a REAL `variants.id`, preloaded once.
    ///
    /// `OnboardingFlowModel.resolveVariant` is synchronous, so the lookup has to
    /// already be in memory when the user taps a shade. Foundation only: the
    /// anchor question asks for a foundation and nothing else uses this.
    private var anchorVariants: [String: UUID] = [:]

    /// Clears everything a signed-in session held (GLO-213) and hands the
    /// screen to FLOW 1's hook — the sign-in screen — on the next frame.
    ///
    /// Sean, Sep 2: *"Signing out should immediately take the user back to
    /// the signin page."* It did not. This used to nil the client and stop,
    /// which left `phase == .ready` and `needsOnboarding == false`, so the
    /// shell went on rendering the tabs: the `you` tab is `if let client`
    /// and drew nothing, and discover kept its stale model. Signed out, as
    /// far as the screen could tell, meant "the profile went blank".
    ///
    /// **The client stays.** `client.signOut()` already ended the Supabase
    /// session; what is left is a `GlossedClient` with no user, which is
    /// exactly what the hook's Apple and phone doors sign in through — the
    /// same thing `readyWithoutAccount` hands the flow on a device with the
    /// dev sign-in off (#499). Nil would make the hook unmountable
    /// (`onboardingFlow` is `if let client` too).
    ///
    /// Deliberately does NOT call `boot()`. The debug build signs in as
    /// maya automatically, so re-booting would put the user straight back
    /// where they were and make sign out look broken — a tap that appears to
    /// do nothing is worse than no button.
    func signedOut() {
        // Whatever queued under the old user goes out before the tracker
        // is dropped; a post after sign-out would be unauthenticated anyway.
        flushTracker()
        tracker = nil
        shelfModel = nil
        discoverModel = nil
        shelfItemCount = 0
        needsOnboarding = true
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
                // The dev sign-in is the simulator's convenience, not the
                // phone's. A device build passes `GLOSSED_DEV_SIGN_IN=0`
                // (baked into the bundle like the keys), and then a launch
                // with no persisted session goes to FLOW 1 to make an
                // account with Sign in with Apple — the real path, on the
                // real stack, for Sean to test as a new user (Sept 2).
                if Self.devSignInIsOff(environment) {
                    if await readyWithoutAccount(booted, config: config) {
                        return
                    }
                } else {
                    try await booted.signIn(email: "maya@local.test", password: "password")
                }
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
                // Before the shelf, because the shell decides between FLOW 1
                // and the tabs on it and a wrong first frame is a flash of the
                // wrong app.
                needsOnboarding = try await Self.needsOnboarding(
                    ProfileRepository(client: booted), environment: environment
                )
                anchorVariants = await Self.loadAnchorVariants(CatalogRepository(client: booted))
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
        shelfItemCount = rows.count
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

    /// Nil profile means the quiz was never answered. The env override exists
    /// because both seeded accounts already have a profiles row (GLO-182), so
    /// without it the flow is unreachable in every drive this project makes.
    /// The phone's boot when no account is signed in: FLOW 1 makes one. A
    /// session the keychain kept from an earlier dev build is maya's, not
    /// the person's — iOS keeps keychain items across an uninstall — so it
    /// is ended, not honoured. False when a real session exists.
    private func readyWithoutAccount(_ booted: GlossedClient, config: GlossedConfig) async -> Bool {
        if await (try? booted.requireUserID()) == Self.seededDevUserID {
            try? await booted.signOut()
        }
        guard await (try? booted.requireUserID()) == nil else { return false }
        client = booted
        needsOnboarding = true
        anchorVariants = await Self.loadAnchorVariants(CatalogRepository(client: booted))
        tracker = Tracker(poster: TrackIngestPoster(client: booted))
        imageBase = config.supabaseURL.appending(path: "storage/v1/object/public/catalog")
        phase = .ready
        return true
    }

    /// `seed.sql`'s maya — the dev sign-in's user, and the one account a
    /// phone must never keep.
    private static let seededDevUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")

    /// `GLOSSED_DEV_SIGN_IN=0` in the launch environment or, for a phone
    /// that launches with none, `GlossedDevSignIn` in the bundle.
    private static func devSignInIsOff(_ environment: [String: String]) -> Bool {
        let fromEnvironment = environment["GLOSSED_DEV_SIGN_IN"]
        let fromBundle = Bundle.main.object(forInfoDictionaryKey: "GlossedDevSignIn") as? String
        return (fromEnvironment ?? fromBundle) == "0"
    }

    private static func needsOnboarding(
        _ profiles: ProfileRepository, environment: [String: String]
    ) async throws -> Bool {
        if environment["GLOSSED_ONBOARDING"] == "1" {
            return true
        }
        return try await profiles.own() == nil
    }

    /// Onboarding wrote a profile, so the reason to show it is gone. Re-reads
    /// rather than assuming: the account step can be skipped, and a flow that
    /// exited without writing should come back next launch.
    func onboardingFinished() async {
        guard let client else { return }
        needsOnboarding = await (try? ProfileRepository(client: client).own()) == nil
        // Signing out drops the tracker with the user it was posting for; a
        // sign-in through the hook is the one path back that does not pass
        // through `boot()`, so the tracker is rebuilt here for the new user.
        if tracker == nil {
            tracker = Tracker(poster: TrackIngestPoster(client: client))
        }
        await reloadShelf()
    }
}
