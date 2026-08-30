import DesignSystem
import SwiftUI

// The + drawer, in its own file for the reason `AppShellDiscover` and
// `AppShellPrivacy` are: `AppShell.swift` sits at SwiftLint's 300-line
// ceiling, and the house remedy is to extract the computed projections rather
// than accrete.

extension AppShell {
    /// Scrim + the ported `ActionDrawer`.
    ///
    /// **The two move separately, and that is the whole point of this shape.**
    /// A scrim and a sheet are different objects: the sheet arrives from
    /// somewhere, the scrim only dims. Wrapping both in one container and
    /// giving the container `.move(edge: .bottom)` made the scrim travel with
    /// the sheet — a hard-edged grey rectangle wiping up the screen, with the
    /// header above the edge left undimmed mid-flight. That was measured off a
    /// simulator recording, not reasoned about: on the way out the wipe is
    /// visible for ~100ms, and on the way in `pop`'s curve fires it so fast it
    /// reads as a flash. It is Sean's "jumpy".
    ///
    /// So the `if` lives INSIDE the ZStack, which is what makes each child an
    /// independent insertion with its own transition, and each transition
    /// carries its own animation:
    ///
    /// - the scrim **fades**, on a curve that does not overshoot. `pop`'s 1.3
    ///   control point sends progress past 1.0 mid-flight, which is right for
    ///   travel and wrong for opacity — opacity clamps at 1, so the overshoot
    ///   becomes a hold, and a hold reads as a snap.
    /// - the sheet **moves**, and keeps `pop`. The overshoot is the kit's own
    ///   (`sheetUp 300ms cubic-bezier(.2,.9,.3,1.3)`), so the bounce is design,
    ///   not defect — measured at 72pt against a 303pt sheet, which is the
    ///   curve's ~24% arriving exactly where the arithmetic says it should.
    ///   What was wrong was the scrim bouncing with it.
    var drawer: some View {
        ZStack(alignment: .bottom) {
            if drawerOpen {
                drawerScrim
                actionDrawer
            }
        }
        .ignoresSafeArea()
    }

    var drawerScrim: some View {
        Button {
            drawerOpen = false
        } label: {
            Rectangle().fill(Tokens.Ink.primary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("close")
        .transition(.opacity.animation(.easeOut(duration: Tokens.Motion.med)))
    }

    /// The four doors. Labels, subtitles, tints and glyphs are `G.drawerOptions`
    /// verbatim; what changes here is where two of them lead.
    ///
    /// **GLO-189 cuts both ways, and this is the direction nobody was watching.**
    /// `new routine` said *"routines land with GLO-21"* while the composer had
    /// been merged for two PRs (#341) and its repository for one more (#342).
    /// Copy that tells you a built thing is unbuilt is exactly as false as copy
    /// that tells you an unbuilt thing is built — it just fails politely, by
    /// hiding work instead of promising it.
    ///
    /// The other two notices were checked before being kept, not assumed:
    ///
    /// - **import** — the screen and its model exist, but `ImportParsing` has
    ///   **no live conformance anywhere in the repo**: a `StubImportParser` in
    ///   `Debug/ScreenData.swift`, a `FakeParser` in the package's tests, and
    ///   nothing else. There is no import Edge Function either, and `onAdd`
    ///   writes nothing. The parse is a server call the app cannot make, so
    ///   every line would come back `noMatch` and the "add N to your shelf"
    ///   button would never appear. That is a door onto a room with no floor;
    ///   the notice is the honest answer and stays until GLO-19.
    /// - **collection** — unbuilt at the time of writing (no repository at all,
    ///   GLO-230) and being built now by its own lane. The notice stays rather
    ///   than a seam, because a seam wired to nothing is the same broken door
    ///   with a nicer name, and swapping the notice for the real screen is one
    ///   line once `features/Collections` exists.
    var actionDrawer: some View {
        ActionDrawer(options: [
            .init(
                label: "add a product",
                subtitle: "search · barcode · near matches · create",
                glyph: .search,
                tint: .mint
            ) {
                drawerOpen = false
                ladderTrip = UUID()
                ladderOpen = true
            },
            .init(
                label: "import a list",
                subtitle: "notes · csv · a screenshot",
                glyph: .file,
                tint: .butter
            ) {
                drawerOpen = false
                notice = "import needs the catalog parser — GLO-19"
            },
            .init(
                label: "new collection",
                subtitle: "group products your way",
                glyph: .folder,
                tint: .lilac
            ) {
                drawerOpen = false
                notice = "collections are being built — GLO-230"
            },
            .init(
                label: "new routine",
                subtitle: "am / pm · ordered steps",
                glyph: .layers,
                tint: .cherry
            ) {
                drawerOpen = false
                routineTrip = UUID()
                routineOpen = true
            }
        ])
        // The kit's sheet curve overshoots on purpose, so mid-flight the sheet
        // lifts ~29pt clear of the bottom edge (measured). While the scrim
        // travelled with it that lift was invisible; a stationary scrim shows
        // it as a strip of dimmed screen under the sheet. This is the sheet's
        // own fill continuing past its bottom — offscreen at rest, and the
        // thing the eye reads as "the sheet is attached to the edge".
        .background(alignment: .bottom) {
            Tokens.Ground.card
                .frame(height: Tokens.Space.s10)
                .offset(y: Tokens.Space.s10)
        }
        .transition(.move(edge: .bottom).animation(Tokens.Motion.pop(Tokens.Motion.med)))
    }

    func noticeCard(_ text: String) -> some View {
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
}
