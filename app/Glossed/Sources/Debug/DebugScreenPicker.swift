#if DEBUG

    import DesignSystem
    import SwiftUI

    /// Debug-build root: every screen that exists, in the states worth looking
    /// at, two taps away.
    ///
    /// Not a design gallery and not a demo. It is the harness for the review
    /// step this project actually relies on — `docs/HANDOFF.md` §5, "run the
    /// thing on a simulator" — which until now cost a hand-written entry point
    /// and a revert every time anyone wanted to look at anything.
    struct DebugScreenPicker: View {
        @State private var showing: ScreenEntry?

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DEBUG BUILD · NOT A SCREEN IN THE APP").eyebrow(color: Tokens.Cherry.deep)
                        ForEach(ScreenCatalog.entries) { entry in
                            row(entry)
                        }
                    }
                    .padding(Tokens.Space.s4)
                }
                .background(Tokens.Ground.milk)
                .navigationTitle("screens")
            }
            .fullScreenCover(item: $showing) { entry in
                // Full screen, not a sheet: a screen shown inside a sheet is
                // inset and rounded, and half the things worth checking are how
                // it meets the edges of the display.
                // Bottom-trailing, not top: every screen in this app puts
                // something in its top-right — the shelf's item count, the item
                // sheet's close, the product page's own chrome — and a harness
                // button sitting on top of the thing you opened the screen to
                // read is a harness that gets in the way of the review it exists
                // for. The bottom-right is the one corner the kit leaves empty
                // under the floating nav's 110pt of room.
                ZStack(alignment: .bottomTrailing) {
                    entry.make()
                    Button("close") { showing = nil }
                        .buttonStyle(.glossed(.secondary, size: .sm))
                        .padding(.trailing, Tokens.Space.s4)
                        .padding(.bottom, Tokens.Space.s5)
                }
            }
        }

        private func row(_ entry: ScreenEntry) -> some View {
            Button { showing = entry } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(Typography.display(15, weight: 700))
                        .foregroundStyle(Tokens.Ink.primary)
                        .multilineTextAlignment(.leading)
                    // The note is the point of the row. A catalog of screen
                    // names would let someone open the happy path and believe
                    // they had checked something.
                    Text(entry.note)
                        .meta()
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Tokens.Space.s3)
                .background(Tokens.Ground.card)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
                )
            }
            .buttonStyle(.plain)
        }
    }
#endif
