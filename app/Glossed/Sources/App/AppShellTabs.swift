import AddLadder
import DataKit
import DesignSystem
import Discover
import Shelf
import SwiftUI

// The tab container and the screens it switches between, lifted out of
// `AppShell.swift` when GLO-245's onboarding branch took that file past
// SwiftLint's 300-line ceiling. The house remedy is to extract rather than
// trim the explanation — the same move `AppShellLadder` made in #401 and
// `ShelfModels` in #422. Stored properties cannot follow, so `@State` stays
// next door.

extension AppShell {
    // MARK: - Tabs

    /// The item sheet owns the bottom of the screen while it is up — a nav
    /// floating over a modal reads as two surfaces fighting (found by looking:
    /// the nav sat on top of the sheet's actions).
    var itemSheetOpen: Bool {
        tab == .shelf && session.shelfModel?.openItem != nil
    }

    /// The active screen hangs off a greedy `Color.clear` rather than sitting
    /// in the ZStack directly, and the shell paints its own ground.
    ///
    /// **Both lines are measured fixes, not tidying.**
    ///
    /// - **The clamp (GLO-252).** `.frame(maxWidth: .infinity)` fills the
    ///   proposal but does not *cap* a child that returns more, so a screen
    ///   wider than the phone made this ZStack wider than the phone — and the
    ///   `.overlay` below inherits that width, which is why the + drawer
    ///   rendered at two different widths depending on the tab behind it.
    ///   Probed with a `GeometryReader` in the drawer on an iPhone 16 Pro:
    ///   **402.0pt over discover, 424.33pt over the shelf** — 11.17pt of spill
    ///   each side, matching the 11pt difference measured between the two
    ///   drawers' title insets. At that width the sheet's own 22pt top corners
    ///   and its 2pt border sit off the screen edges entirely, which is Sean's
    ///   *"doesn't have the rounding at the top I'd expect"* (GLO-255): the
    ///   rounding was always drawn, just not on screen. An `.overlay` is sized
    ///   by its base and an oversized overlay never grows it, so measuring the
    ///   screen against `Color.clear` caps the container while proposing the
    ///   active screen exactly the size it gets today. The screen still bleeds
    ///   past the edges where it means to — the shelf's domain filter is drawn
    ///   that way on purpose.
    /// - **The ground (GLO-256).** Sean's *"narrow vertical rectangle flashes
    ///   between tabs"*. Recorded and counted rather than reasoned about, per
    ///   GLO-241: it appears on **every entry into the `you` tab and on no
    ///   other transition** (3 of 3 entries in one recording, 3–7 frames each),
    ///   and the frame shows a **60pt-wide full-height milk column centred on a
    ///   white window**. 60pt is `ProgressView` plus `OwnProfileView`'s own
    ///   padding: while it is loading, that screen's `ScrollView` takes its
    ///   content's width and its milk background goes with it, leaving the rest
    ///   of the window bare. The shell had no ground of its own, so bare read
    ///   as white. Painting one makes the column the same colour as everything
    ///   around it. The narrow layout itself is `features/Profile`'s to widen.
    var tabs: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay { activeScreen.clearingFloatingNav() }
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
        .onPreferenceChange(FloatingNavTabAnchors.self) { navTabAnchors = $0 }
        .background(Tokens.Ground.milk.ignoresSafeArea())
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
        .fullScreenCover(isPresented: $lookOpen) {
            lookComposer
        }
        // These two arrived on main after this extraction was written, and are
        // carried across by the rebase rather than lost: extracting a block is
        // only safe if it takes the block as it stands now.
        .fullScreenCover(item: $openLook) { open in
            lookPost(open)
        }
        .fullScreenCover(item: $openOwnItem) { item in
            ownItemDetail(item)
        }
        .fullScreenCover(isPresented: $collectionOpen) {
            collectionComposer
        }
        .fullScreenCover(item: $rankingItem) { item in
            faceOff(item)
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

    @ViewBuilder var activeScreen: some View {
        switch tab {
        case .shelf:
            shelfTab
        case .discover:
            discoverTab
        case .you:
            youTab
        }
    }
}
