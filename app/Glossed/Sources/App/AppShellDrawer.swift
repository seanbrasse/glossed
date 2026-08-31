import DesignSystem
import Profile
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

    /// The five doors. The first four are `G.drawerOptions` verbatim — labels,
    /// subtitles, tints and glyphs; what changes there is where two of them
    /// lead.
    ///
    /// **The fifth is Sean's, and it is a stated divergence from the frame.**
    /// Asked where looks are created he answered with the whole list — *"add a
    /// product, import a list, new collection, routine, **post a look**"* —
    /// which overrules the screen map's caption for this drawer (*"posting a
    /// look is not V1"*) and delta 9's four-door list. The caption predates
    /// delta 11, which put looks and the feed in V1, and `tech/00` §2 states
    /// deltas supersede: the caption's reason expired while the caption stayed
    /// standing, which is GLO-242's landing tab exactly. `G.drawerOptions`
    /// still draws four, so the row's label is Sean's and its subtitle and tint
    /// are this lane's; the mark is not invented, `G.ICONS.camera` is the kit's
    /// own (GLO-64).
    ///
    /// **Why the subtitle says what it says.** `post a look` is Sean's word for
    /// the door and it stays, but the composer behind it calls `saveDraft` —
    /// nothing in the app publishes, and `ComposerView`'s own line ("saves to
    /// your account. nothing shows it to anyone yet") is the claim of record.
    /// So the subtitle names what the composer *does* — photos, and tags drawn
    /// from what you already own — and claims nothing about who will see it.
    /// GLO-189's law is the binding one here and it holds in both directions:
    /// no copy on this path implies a look is reviewed, and none implies it is
    /// published either.
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
    /// - **collection** — this bullet said "no repository at all, GLO-230" and
    ///   that expired when #387 merged one. The profile's collections tab reads
    ///   it and draws real cards. What is still missing is the screen that
    ///   MAKES a collection, which is GLO-21's remaining half, so the door
    ///   still ends in a notice — but the notice now names the ticket that is
    ///   open rather than the one that closed, and it is the same string the
    ///   profile's `+` uses because both route through `AppShell.compose`.
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
                // Routed through the profile's crossing so the two `+`
                // affordances cannot disagree. The old literal here said
                // `collections are being built — GLO-230` and had been false
                // since #387 merged that ticket's repository — GLO-189 in the
                // direction nobody watches, hiding built work rather than
                // promising unbuilt work. See `AppShell.compose`.
                compose(.collection)
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
            },
            .init(
                label: "post a look",
                subtitle: "photos · tag what you own",
                glyph: .camera,
                // Five doors, four kit tints, so one repeats. Mint rather than
                // cherry: cherry is the app's one loud voice and `new routine`
                // already wears it here, so a second would sit directly under
                // the first and read as two pops in one sheet. Mint's twin is
                // four rows away, which is as far apart as this list goes.
                tint: .mint
            ) {
                drawerOpen = false
                lookTrip = UUID()
                lookOpen = true
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
