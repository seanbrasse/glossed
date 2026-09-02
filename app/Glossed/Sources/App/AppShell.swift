import AddLadder
import DataKit
import DesignSystem
import Discover
import Shelf
import SwiftUI

/// The app: three tabs + the plus button (screen map FLOW 2), live on the
/// session `AppSession` boots.
///
/// Built to `G.navTabs` and the kit's `ActionDrawer` frame, and checked
/// against both this session by reading `screens.jsx` rather than from
/// memory. `G.navTabs` is `sparkles` · `shelf` · `<Avatar name="maya"
/// size={26}/>`, in that order, and `FloatingNav` draws exactly that.
///
/// This comment used to claim a divergence that no longer existed — *"the
/// 'you' tab's nav icon is an SF Symbol rather than the kit's Avatar
/// (`FloatingNav.Tab` carries a symbol name)"*. `Tab` carries a `Glyph`, and
/// `.avatar(name:)` renders `Avatar(name:size: 26)`. The port happened and
/// the note describing its absence outlived it, which is the same failure the
/// drawer's "routines land with GLO-21" was: **a true statement about the
/// past left standing as a claim about the present.**
///
/// The one stated divergence that IS current: an unbuilt tab names its ticket
/// instead of rendering an empty screen — a dev shell should say what does
/// not exist yet.
struct AppShell: View {
    enum ShellTab: String, CaseIterable {
        case discover, stylist, shelf, you
    }

    @State var session = AppSession()
    @Environment(\.scenePhase) private var scenePhase
    /// Tab 1, per the screen map's `tab 1 · discover`.
    ///
    /// This was `.shelf`, on the reasoning "the kit's tab 1 is discover, but
    /// discover is GLO-20 — until it exists the shelf is the honest landing."
    /// That reasoning was right and its premise has expired: discover is
    /// built and merged (#314, #371).
    ///
    /// **Why one default serves both entry paths.** The map draws two, and
    /// they disagree less than they look. A returning user is delta 3
    /// verbatim — *"two screens and they land on discover, with their anchor,
    /// shelf and rankings intact"* — and that is the path this shell is on
    /// today, since `AppSession` signs in as an account that already exists.
    /// A brand-new one does not get a default at all: delta 4 ends onboarding
    /// at `welcome`, whose three doors are *build · import · browse*, so the
    /// first landing is something they **chose**. A choice arrives as an
    /// argument when GLO-18's flow reaches the shell; it is not a second
    /// constant to guess at now, and guessing `.shelf` for it would only be
    /// right for one of the three doors.
    /// Internal, not private: `AppShellOnboarding` routes FLOW 1's exit to a
    /// tab, and the tour changes tabs as it walks. Same reason `drawerOpen`
    /// and `openProduct` already are.
    @State var tab = ShellTab.discover
    @State var drawerOpen = false
    @State var privacyOpen = false
    @State var handleOpen = false
    /// Internal, not private: the drawer's doors live in `AppShellDrawer.swift`
    /// now, and an extension in another file cannot see a private member. Same
    /// reason `drawerOpen` and `openProduct` already are.
    @State var ladderOpen = false
    /// Regenerated every time the drawer opens the ladder: the cover keeps
    /// its content's identity across presentations, so without this a second
    /// "add a product" resumes the first trip — stale query, stale rung, and
    /// a reused log idempotency key across two distinct intentions (GLO-96).
    @State var ladderTrip = UUID()
    /// What the ladder's search rung opens with — a pick's name from the
    /// empty shelf, or nothing. Cleared when the ladder closes.
    @State var ladderSeed = ""
    /// One line the shell owes you once the drawer has closed: a door that is
    /// not built yet naming its ticket, or a door that ran saying what it did.
    /// The second case arrived with GLO-254 — a composer that dismisses itself
    /// on success answers "did it work?" with silence.
    @State var notice: String?
    /// The routine composer, the drawer's fourth door (#341/#342).
    @State var routineOpen = false
    /// `ladderTrip`'s reasoning at the second cover: a new trip is a new
    /// composer, so a second "new routine" starts empty rather than resuming
    /// the first one's title, steps and minted routine id.
    @State var routineTrip = UUID()
    /// The collection composer, the drawer's third door (GLO-21).
    @State var collectionOpen = false
    /// `routineTrip`'s reasoning again: a new trip is a new composer, so a
    /// second "new collection" starts empty rather than resuming the first
    /// one's name, tint and picked products.
    @State var collectionTrip = UUID()
    /// The look composer, the drawer's fifth door (GLO-254, Sean's ruling).
    @State var lookOpen = false
    /// The look the profile opened as a post (GLO-266).
    @State var openLook: OpenLook?
    /// The collection or routine the profile opened (GLO-272's click-in).
    @State var openOwnItem: OpenOwnItem?
    /// The same reasoning again, and it bites harder here: `LooksStore.live`
    /// mints the look's id once per store, so a reused composer would re-upload
    /// a second look's photos into the first look's R2 namespace.
    @State var lookTrip = UUID()
    /// The row the ladder just wrote, held until the cover dismisses — asking
    /// "did it fit?" under a closing full-screen cover is a question nobody
    /// sees.
    @State var pendingLog: LoggedShelfItem?
    /// The shelf item whose product page is open (GLO-151). Held here rather
    /// than in `Shelf` because a feature cannot import another feature: the
    /// shelf hands the tap up, and the app owns the crossing.
    @State var openProduct: ShelfItem?
    /// The shelf item the face-off is ranking (GLO-240).
    ///
    /// **`rank it` was wired to `dismiss` at all three call sites**, so the
    /// only entrance to a screen built in GLO-17 closed the page instead of
    /// opening it. `features/Ranking` is linked into this target and was
    /// imported by nothing. Same crossing as `openProduct`: the page hands the
    /// tap up and the app owns what it opens.
    @State var rankingItem: ShelfItem?
    /// A discover row opening as a page (GLO-20). Distinct from
    /// `openProduct` because there is no ShelfItem — the fit control stays
    /// read-only via the nil `userItemID`, exactly the case ProductPageItem
    /// documented before this path existed.
    @State var openCatalogPage: CatalogPage?
    @State var catalogVariantChoice: CatalogVariantChoice?
    @State var showTrending = false
    /// The category board the product page's "leaderboard" button opened.
    @State var openBoard: BoardContext?
    /// The board discover's own `leaderboards →` opened. Its own state on
    /// purpose: `openBoard` presents from inside the product page's cover,
    /// and one binding driving two sheets in two contexts is a race.
    @State var discoverBoard: BoardContext?
    /// Non-nil while the fit prompt is up: the shelf row it writes to.
    /// Internal for the reason `tab` is: the container that presents it moved
    /// to `AppShellTabs` when this file hit the ceiling.
    @State var fitPromptItemID: UUID?
    /// Each nav tab's centre, published by `FloatingNav` itself (GLO-245).
    ///
    /// **Not derived from the nav's frame.** That frame includes the `+`, so
    /// dividing it into equal parts puts the tour's pointer between two tabs —
    /// which is what it did, on screen, before the nav started reporting this.
    /// The only honest source is the thing that lays the tabs out.
    @State var navTabAnchors: [String: CGFloat] = [:]
    /// Bumped when a cover that can write what the profile shows closes —
    /// a composer, a card's editor — and handed to `OwnProfileView` as its
    /// `reloadKey` (GLO-278). The shell presents every one of those covers,
    /// so it is the one place that knows the moment.
    @State var profileReloadTrip = UUID()

    var body: some View {
        content
            .task { await session.boot() }
            // Background AND foreground, per tech/06 §2 — background so a
            // closed app loses nothing, foreground so a long-lived queue
            // from last time goes out before new events pile on it.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background || phase == .active {
                    session.flushTracker()
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .connecting:
            VStack(spacing: Tokens.Space.s3) {
                ProgressView()
                Text("signing in as maya@local.test").meta()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Ground.milk)
        case let .failed(message):
            failedView(message)
        case .ready:
            // FLOW 1 owns the whole screen when this account has never
            // answered the quiz — the tour stop is the one exception, and it
            // asks for `tabs` back so it can draw over the real app.
            if session.needsOnboarding {
                onboardingFlow
            } else {
                tabs
            }
        }
    }

    /// The anchor gate, checked after the cover closes: no category (the
    /// matched-barcode gap) or a non-anchor category means no prompt, and a
    /// failed category read skips quietly — the prompt is a follow-up ask,
    /// not a claim, and blocking the shelf over it would cost more than the
    /// missed answer.
    func askFitIfAnchor() {
        guard let logged = pendingLog else { return }
        pendingLog = nil
        guard let categoryID = logged.categoryID, let client = session.client else { return }
        Task {
            let categories = await (try? CatalogRepository(client: client).categories(domain: nil)) ?? []
            guard categories.first(where: { $0.id == categoryID })?.isAnchor == true else { return }
            fitPromptItemID = logged.userItemID
        }
    }
}
