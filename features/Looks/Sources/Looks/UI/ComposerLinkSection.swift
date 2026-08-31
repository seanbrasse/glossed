import DesignSystem
import SwiftUI

// The composer's link section (0050), split from `ComposerView` for the
// 300-line ceiling — `ComposerTagSection`'s reason and its neighbor.

extension ComposerView {
    /// "Looks can also have routines or collections linked to them" —
    /// GLO-266's last line, Sean's ask verbatim. Chips, on/off, own things
    /// only (the write policies refuse anything else, so the offer must
    /// too). Absent entirely when there is nothing to offer.
    @ViewBuilder var linkSection: some View {
        if !model.linkables.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text("LINK YOUR ROUTINES + COLLECTIONS").eyebrow()
                if !model.linkables.routines.isEmpty {
                    linkChips(
                        model.linkables.routines,
                        isOn: { model.linkedRoutineIDs.contains($0) },
                        toggle: { model.toggleRoutine($0) }
                    )
                }
                if !model.linkables.collections.isEmpty {
                    linkChips(
                        model.linkables.collections,
                        isOn: { model.linkedCollectionIDs.contains($0) },
                        toggle: { model.toggleCollection($0) }
                    )
                }
                Text("a link shows only where both sides are visible.").meta()
            }
        }
    }

    func linkChips(
        _ picks: [LinkablePick],
        isOn: @escaping (UUID) -> Bool,
        toggle: @escaping (UUID) -> Void
    ) -> some View {
        FlowLayoutCompat(spacing: Tokens.Space.s2) {
            ForEach(picks) { pick in
                Button(pick.title) { toggle(pick.id) }
                    .buttonStyle(.plain)
                    .font(Typography.mono(12))
                    .foregroundStyle(Tokens.Ink.primary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, Tokens.Space.s3)
                    .background(
                        Capsule().fill(isOn(pick.id) ? Tokens.Cherry.soft : Tokens.Ground.card)
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            isOn(pick.id) ? Tokens.Cherry.deep : Tokens.Ink.primary,
                            lineWidth: isOn(pick.id) ? Tokens.Border.thin : Tokens.Border.hair
                        )
                    )
                    .accessibilityAddTraits(isOn(pick.id) ? .isSelected : [])
            }
        }
    }
}
