import DesignSystem
import SwiftUI

/// A profile with nothing on it yet — and the `+` Sean asked for (GLO-261).
///
/// > "In an empty state, you'll have a plus button that directs you to make a
/// > look, collection, routine, etc."
///
/// **The `+` lives here and nowhere else on this screen.** The shell already
/// carries a global `+` drawer on every tab (GLO-254), so a second one on a
/// populated profile would be two controls doing one thing a thumb's width
/// apart. Empty is the one state where the shell's `+` is not obviously the
/// answer, which is exactly the state Sean named.
///
/// The profile cannot open a composer — features never import features — so
/// each door hands its case up and the app layer opens the drawer it has.
struct ProfileEmptyState: View {
    let onCompose: ((ProfileComposable) -> Void)?

    var body: some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text("nothing here yet")
                    .font(Typography.display(Typography.Size.h3))
                    .foregroundStyle(Tokens.Ink.primary)
                // What the profile IS, which is the honest empty-state line:
                // it names the four things that land here and stops. It does
                // not say who will see them — the tab marks say that, once
                // there is a tab to mark.
                Text("your looks, collections and routines show up here.")
                    .meta()
                if let onCompose {
                    doors(onCompose)
                }
            }
        }
    }

    /// One row: the kit's `+` beside the three things it can start.
    ///
    /// The copy names the thing and stops — `a look`, not `share a look` and
    /// not `post a look to your followers`. Publishing is unmoderated by
    /// decision pending GLO-26, and promising an audience would be a claim
    /// this build cannot keep (GLO-189). #399 settled that wording for the
    /// button Sean has now rejected; the reasoning outlived the button.
    private func doors(_ onCompose: @escaping (ProfileComposable) -> Void) -> some View {
        // Horizontal rather than wrapped: driven at 402pt, the three pills plus
        // the glyph overflow the card and `a collection` broke across two lines
        // inside its own capsule. A pill whose words wrap reads as two pills.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s2) {
                PlusIcon(size: 18)
                    .foregroundStyle(Tokens.Ink.primary)
                    .accessibilityHidden(true)
                ForEach(ProfileComposable.allCases, id: \.self) { what in
                    Button(what.label) { onCompose(what) }
                        .buttonStyle(.glossed(what == .look ? .primary : .secondary, size: .sm))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            // Room for the buttons' hard shadow, which sits outside their
            // capsules and would otherwise clip against the scroller's edge.
            .padding(.trailing, Tokens.Shadow.sm)
            .padding(.bottom, Tokens.Shadow.sm)
        }
        .padding(.top, Tokens.Space.s1)
    }
}

/// What the empty state's `+` can start.
///
/// The profile cannot open a composer — features never import features — so
/// the `+` hands the choice up and the app layer opens the drawer door it
/// already has (GLO-254 shipped `post a look`). A case with no callback wired
/// is not offered.
public enum ProfileComposable: String, CaseIterable, Sendable {
    case look, collection, routine

    /// GLO-189: the copy names the thing and stops. It does not say the look
    /// will be seen, reviewed, or reach anyone — publishing is unmoderated by
    /// decision pending GLO-26, and promising an audience would be false.
    public var label: String {
        "a \(rawValue)"
    }
}
