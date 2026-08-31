import DesignSystem
import SwiftUI

/// The profile's tab strip, where every tab carries its own scope (GLO-261).
///
/// **Why this is not `Segmented`.** The kit's control takes `[String]` and
/// draws one word per segment, and that is the whole of its contract. The
/// mark is the point of this strip: GLOSSED has four per-surface scopes where
/// Instagram has one account switch, so "your profile is what a stranger sees"
/// is only true if the difference is on the screen. Widening `Segmented` to
/// carry a second line would push a profile-shaped concern into a primitive
/// six other screens use. The chrome is copied from it exactly — card fill,
/// 2pt ink border, hard shadow, capsule, ink-filled selection — so it reads as
/// the same control it is a variant of.
///
/// **Why the scope is a word and not a glyph.** Three states have to be told
/// apart at a glance, and `only you` / `friends` / `public` are already the
/// app's words for them (`PrivacyScope.label`, Sean's Aug 29 wording). The kit
/// has no lock, eye or globe in `G.ICONS` to port, and no SF Symbol may be
/// reached for (GLO-64). A word nobody has to learn beats a glyph nobody
/// agrees on.
///
/// The strip scrolls horizontally because four tabs each carrying two lines do
/// not fit 402pt, and a mark that truncates is a mark that misleads.
struct ProfileTabBar: View {
    let tabs: [ProfileTab]
    let mark: (ProfileTab) -> ProfileScopeMark?
    @Binding var selection: ProfileTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(tabs, id: \.self) { segment($0) }
            }
            .padding(3)
            .background(Tokens.Ground.card)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
            .background(
                Capsule().fill(Tokens.Ink.primary)
                    .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
            )
            // The shadow sits outside the capsule; without room for it the
            // scroller clips the offset copy against its own edge.
            .padding(.trailing, Tokens.Shadow.sm)
            .padding(.bottom, Tokens.Shadow.sm)
        }
    }

    private func segment(_ tab: ProfileTab) -> some View {
        let on = tab == selection
        return Button { selection = tab } label: {
            VStack(spacing: 1) {
                Text(tab.label)
                    .font(Typography.control(13))
                    .foregroundStyle(on ? Color.white : Tokens.Ink.primary)
                if let mark = mark(tab) {
                    Text(mark.label)
                        .font(Typography.mono(9.5))
                        // Softened against its own ground rather than given a
                        // colour of its own: the mark states a fact about the
                        // tab, and a coloured one would read as a warning
                        // about it.
                        .foregroundStyle(on ? Color.white.opacity(0.75) : Tokens.Ink.soft)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Tokens.Space.s3)
            .frame(minHeight: 40)
            .background(on ? Tokens.Ink.primary : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.pop(), value: on)
        // The mark is spoken in full. Read as it is drawn, VoiceOver would say
        // "looks public" — which sounds like an adjective on the tab name.
        .accessibilityLabel(
            mark(tab).map { "\(tab.label), \($0.spokenLabel)" } ?? tab.label
        )
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
