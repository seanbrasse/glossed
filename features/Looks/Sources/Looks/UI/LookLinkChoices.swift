import DesignSystem
import SwiftUI

// The single-choice link pickers (0054: a look holds ONE routine and ONE
// collection) in Sean's Aug 31 shapes: "these should be separate … Ideally
// the collection will show up in its card form, routine by its label."
// Shared by the composer and the edit screen — same feature, one drawing.

/// A ROUTINE — label chips, radio semantics: tap selects, tap again clears,
/// tapping another replaces.
struct RoutineChoiceRow: View {
    let picks: [LinkablePick]
    @Binding var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("LINK A ROUTINE").eyebrow()
            FlowLayoutCompat(spacing: Tokens.Space.s2) {
                ForEach(picks) { pick in
                    chip(pick)
                }
            }
        }
    }

    private func chip(_ pick: LinkablePick) -> some View {
        let isOn = selection == pick.id
        return Button(pick.title) {
            selection = isOn ? nil : pick.id
        }
        .buttonStyle(.plain)
        .font(Typography.mono(12))
        .foregroundStyle(Tokens.Ink.primary)
        .padding(.vertical, 6)
        .padding(.horizontal, Tokens.Space.s3)
        .background(Capsule().fill(isOn ? Tokens.Cherry.soft : Tokens.Ground.card))
        .overlay(
            Capsule().strokeBorder(
                isOn ? Tokens.Cherry.deep : Tokens.Ink.primary,
                lineWidth: isOn ? Tokens.Border.thin : Tokens.Border.hair
            )
        )
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A COLLECTION — its card form: the tinted card the collections tab draws,
/// small, in a horizontal rail. Same radio semantics as the routine chips.
struct CollectionChoiceRow: View {
    let picks: [LinkablePick]
    @Binding var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("LINK A COLLECTION").eyebrow()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.s2) {
                    ForEach(picks) { pick in
                        card(pick)
                    }
                }
            }
        }
    }

    private func card(_ pick: LinkablePick) -> some View {
        let isOn = selection == pick.id
        return Button {
            selection = isOn ? nil : pick.id
        } label: {
            GlossedCard(tint: Self.tint(pick.tintWord), pop: isOn, padding: Tokens.Space.s3) {
                CollectionChoiceCardBody(pick: pick)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityLabel("\(pick.title)\(isOn ? ", linked" : "")")
    }

    /// `CollectionCard.tint`'s switch, restated here because features never
    /// import features — the four words are the kit's four soft fills, and
    /// `GlossedCard` owns the colors either way. Spelled through the named
    /// body view for `CollectionCard`'s own reason: `Tint` nests inside a
    /// generic, so each specialisation has its own.
    static func tint(_ word: String?) -> GlossedCard<CollectionChoiceCardBody>.Tint {
        switch word {
        case "butter": .butter
        case "cherry": .cherry
        case "mint": .mint
        case "lilac": .lilac
        default: .plain
        }
    }
}

/// Bottom-aligned like the collections tab's own card — this IS its card
/// form, small.
struct CollectionChoiceCardBody: View {
    let pick: LinkablePick

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Spacer(minLength: 0)
            Text(pick.title)
                .font(Typography.display(Typography.Size.small))
                .foregroundStyle(Tokens.Ink.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let n = pick.itemN {
                Text("\(n) \(n == 1 ? "product" : "products")")
                    .meta()
            }
        }
        .frame(width: 120, alignment: .bottomLeading)
        .frame(minHeight: 72, alignment: .bottomLeading)
    }
}
