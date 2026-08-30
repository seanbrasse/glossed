import AddLadder
import DataKit
import DesignSystem
import Discover
import Shelf
import SwiftUI

/// The app: three tabs + the plus button (screen map FLOW 2), live on the
/// session `AppSession` boots.
///
/// Built to `G.navTabs` and the kit's `ActionDrawer` frame. Stated
/// divergences: the "you" tab's nav icon is an SF Symbol rather than the
/// kit's Avatar (`FloatingNav.Tab` carries a symbol name; GLO-64 territory),
/// and the unbuilt tabs say which ticket builds them instead of rendering an
/// empty screen — a dev shell should say what does not exist yet.
struct AppShell: View {
    enum ShellTab: String, CaseIterable {
        case discover, shelf, you
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
    @State private var tab = ShellTab.discover
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
    /// One line naming the ticket for a drawer option that is not built yet.
    @State var notice: String?
    /// The routine composer, the drawer's fourth door (#341/#342).
    @State var routineOpen = false
    /// `ladderTrip`'s reasoning at the second cover: a new trip is a new
    /// composer, so a second "new routine" starts empty rather than resuming
    /// the first one's title, steps and minted routine id.
    @State var routineTrip = UUID()
    /// The row the ladder just wrote, held until the cover dismisses — asking
    /// "did it fit?" under a closing full-screen cover is a question nobody
    /// sees.
    @State private var pendingLog: LoggedShelfItem?
    /// The shelf item whose product page is open (GLO-151). Held here rather
    /// than in `Shelf` because a feature cannot import another feature: the
    /// shelf hands the tap up, and the app owns the crossing.
    @State var openProduct: ShelfItem?
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
    @State private var fitPromptItemID: UUID?

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
            tabs
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("the local stack is not answering").font(Typography.display(24))
            Text(message).meta()
            Text(
                "run `make setup`, then launch with SUPABASE_PUBLISHABLE_KEY from "
                    + "`supabase status` in the environment. if sign-in fails, `supabase db reset` first."
            ).meta()
        }
        .padding(Tokens.Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.Ground.milk)
    }

    // MARK: - Tabs

    /// The item sheet owns the bottom of the screen while it is up — a nav
    /// floating over a modal reads as two surfaces fighting (found by looking:
    /// the nav sat on top of the sheet's actions).
    private var itemSheetOpen: Bool {
        tab == .shelf && session.shelfModel?.openItem != nil
    }

    private var tabs: some View {
        ZStack(alignment: .bottom) {
            activeScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clearingFloatingNav()
            if !itemSheetOpen {
                FloatingNav(
                    tabs: [
                        .init(id: ShellTab.discover, label: "discover", glyph: .discover),
                        .init(id: ShellTab.shelf, label: "shelf", glyph: .shelf),
                        // maya = the dev sign-in; real names are GLO-204's.
                        .init(id: ShellTab.you, label: "you", glyph: .avatar(name: "maya"))
                    ],
                    active: $tab,
                    onPlus: { drawerOpen = true }
                )
                .padding(.bottom, Tokens.Space.s3)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Tokens.Motion.pop(Tokens.Motion.med), value: itemSheetOpen)
        .overlay {
            drawer
            if let notice {
                noticeCard(notice)
            }
        }
        .animation(Tokens.Motion.pop(Tokens.Motion.med), value: drawerOpen)
        .privacySheet(isPresented: $privacyOpen, client: session.client)
        .handleClaimSheet(isPresented: $handleOpen, client: session.client)
        .fullScreenCover(isPresented: $ladderOpen, onDismiss: askFitIfAnchor) {
            ladderFlow
        }
        .fullScreenCover(isPresented: $routineOpen) {
            routineComposer
        }
        .fullScreenCover(item: $openProduct) { item in
            if let client = session.client {
                productPage(
                    for: item,
                    rankedInCategory: session.shelfModel?.rankedCount(inCategoryOf: item),
                    client: client
                ) { closeProductPage() }
            }
        }
        .overlay {
            if let itemID = fitPromptItemID, let client = session.client {
                FitPromptCard(
                    store: .repository(ShelfRepository(client: client)),
                    itemID: itemID,
                    onDone: { fitPromptItemID = nil }
                )
            }
        }
    }

    /// The anchor gate, checked after the cover closes: no category (the
    /// matched-barcode gap) or a non-anchor category means no prompt, and a
    /// failed category read skips quietly — the prompt is a follow-up ask,
    /// not a claim, and blocking the shelf over it would cost more than the
    /// missed answer.
    private func askFitIfAnchor() {
        guard let logged = pendingLog else { return }
        pendingLog = nil
        guard let categoryID = logged.categoryID, let client = session.client else { return }
        Task {
            let categories = await (try? CatalogRepository(client: client).categories(domain: nil)) ?? []
            guard categories.first(where: { $0.id == categoryID })?.isAnchor == true else { return }
            fitPromptItemID = logged.userItemID
        }
    }

    @ViewBuilder private var activeScreen: some View {
        switch tab {
        case .shelf:
            shelfTab
        case .discover:
            discoverTab
        case .you:
            youTab
        }
    }

    // MARK: - The ladder

    @ViewBuilder private var ladderFlow: some View {
        if let client = session.client {
            LadderFlowView(
                catalog: CatalogRepository(client: client),
                shelf: ShelfRepository(client: client),
                tracker: session.tracker,
                // GLO-93: a scanned miss asks the catalog-fill function
                // before the ladder falls through. The function itself
                // fails closed (no key, exhausted budget, unreachable all
                // answer "nothing to add"), so wiring it is unconditional.
                fill: BarcodeFillService(client: client),
                onClose: { ladderOpen = false },
                onShelfChanged: { session.refreshShelf() },
                onLogged: { pendingLog = $0 }
            )
            // Search rows and the variant sheet compose real cutout URLs
            // from this — the same base the shelf reads with (GLO-83).
            .environment(\.catalogImageBase, session.imageBase)
            // One trip per presentation — see `ladderTrip`.
            .id(ladderTrip)
        }
    }
}
