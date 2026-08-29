import AddLadder
import DataKit
import DesignSystem
import Privacy
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
    /// The kit's tab 1 is discover, but discover is GLO-20 — until it exists
    /// the shelf is the honest landing.
    @State private var tab = ShellTab.shelf
    @State private var drawerOpen = false
    @State private var privacyOpen = false
    @State private var ladderOpen = false
    /// Regenerated every time the drawer opens the ladder: the cover keeps
    /// its content's identity across presentations, so without this a second
    /// "add a product" resumes the first trip — stale query, stale rung, and
    /// a reused log idempotency key across two distinct intentions (GLO-96).
    @State private var ladderTrip = UUID()
    /// One line naming the ticket for a drawer option that is not built yet.
    @State private var notice: String?
    /// The row the ladder just wrote, held until the cover dismisses — asking
    /// "did it fit?" under a closing full-screen cover is a question nobody
    /// sees.
    @State private var pendingLog: LoggedShelfItem?
    /// The shelf item whose product page is open (GLO-151). Held here rather
    /// than in `Shelf` because a feature cannot import another feature: the
    /// shelf hands the tap up, and the app owns the crossing.
    @State var openProduct: ShelfItem?
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
            if !itemSheetOpen {
                FloatingNav(
                    tabs: [
                        .init(id: ShellTab.discover, label: "discover", systemImage: "sparkles"),
                        .init(id: ShellTab.shelf, label: "shelf", systemImage: "square.split.1x2"),
                        .init(id: ShellTab.you, label: "you", systemImage: "person.crop.circle")
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
            if drawerOpen {
                drawer
            }
            if let notice {
                noticeCard(notice)
            }
        }
        .animation(Tokens.Motion.pop(Tokens.Motion.med), value: drawerOpen)
        .sheet(isPresented: $privacyOpen) {
            if let client = session.client {
                PrivacyView(store: .live(PrivacyRepository(client: client)))
            }
        }
        .fullScreenCover(isPresented: $ladderOpen, onDismiss: askFitIfAnchor) {
            ladderFlow
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
            if let model = session.shelfModel {
                // Recreated when the model is (the ladder landed something):
                // `ShelfView` snapshots the reference at init, so identity is
                // what tells SwiftUI this is a new shelf.
                ShelfView(model: model, onOpenProduct: { openProduct = $0 })
                    .id(ObjectIdentifier(model))
            } else {
                Text("the shelf came back empty — pull the stack up and relaunch").meta()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Ground.milk)
            }
        case .discover:
            unbuiltTab("discover", ticket: "GLO-20", line: "picked for you, from your anchor")
        case .you:
            // The profile itself is GLO-21 and unbuilt. Privacy (GLO-119) is
            // built, so it gets a door rather than waiting for the room — an
            // unreachable screen is a screen nobody can check.
            VStack(spacing: Tokens.Space.s4) {
                unbuiltTab("you", ticket: "GLO-21", line: "profile · collections · settings")
                if session.client != nil {
                    Button("privacy") { privacyOpen = true }
                        .buttonStyle(.glossed(.secondary))
                }
            }
        }
    }

    /// An unbuilt tab names its ticket. The tab exists because the nav is the
    /// kit's; the screen does not, and pretending otherwise helps nobody.
    private func unbuiltTab(_ name: String, ticket: String, line: String) -> some View {
        VStack(spacing: Tokens.Space.s2) {
            Text(name).font(Typography.display(30)).foregroundStyle(Tokens.Ink.primary)
            Text(line).meta()
            Badge("not built yet · \(ticket)", tone: .lilac)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Ground.milk)
    }

    // MARK: - The + drawer

    /// Scrim + the ported `ActionDrawer`, presented the way the item sheet is.
    private var drawer: some View {
        ZStack(alignment: .bottom) {
            Button {
                drawerOpen = false
            } label: {
                Rectangle().fill(Tokens.Ink.primary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("close")

            ActionDrawer(options: [
                .init(
                    label: "add a product",
                    subtitle: "search · barcode · near matches · create",
                    systemImage: "magnifyingglass",
                    tint: .mint
                ) {
                    drawerOpen = false
                    ladderTrip = UUID()
                    ladderOpen = true
                },
                .init(
                    label: "import a list",
                    subtitle: "notes · csv · a screenshot",
                    systemImage: "doc.text",
                    tint: .butter
                ) {
                    drawerOpen = false
                    notice = "import lands with GLO-19"
                },
                .init(
                    label: "new collection",
                    subtitle: "group products your way",
                    systemImage: "folder",
                    tint: .lilac
                ) {
                    drawerOpen = false
                    notice = "collections land with GLO-21"
                },
                .init(
                    label: "new routine",
                    subtitle: "am / pm · ordered steps",
                    systemImage: "square.stack",
                    tint: .cherry
                ) {
                    drawerOpen = false
                    notice = "routines land with GLO-21"
                }
            ])
        }
        .ignoresSafeArea()
        .transition(.move(edge: .bottom))
    }

    private func noticeCard(_ text: String) -> some View {
        VStack(spacing: Tokens.Space.s3) {
            Text(text).meta()
            Button("ok") { notice = nil }
                .buttonStyle(.glossed(.secondary))
        }
        .padding(Tokens.Space.s5)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Ink.primary.opacity(0.4))
        .ignoresSafeArea()
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
