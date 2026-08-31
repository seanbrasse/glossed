import DesignSystem
import SwiftUI

// The post's GOES WITH section (0050), split from `LookPostView` for the
// 300-line ceiling.

extension LookPostView {
    /// "Looks can also have routines or collections linked to them." Chips
    /// under the caption — attribution, never a claim (GLO-196): no counts,
    /// no evidence chrome, and a link the policies hid simply is not here.
    @ViewBuilder var linkedSection: some View {
        if !linkedRoutines.isEmpty || !linkedCollections.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text("GOES WITH").eyebrow()
                FlowLayoutCompat(spacing: Tokens.Space.s2) {
                    ForEach(linkedRoutines) { pick in
                        linkChip(pick.title, kind: "routine")
                    }
                    ForEach(linkedCollections) { pick in
                        linkChip(pick.title, kind: "collection")
                    }
                }
            }
        }
    }

    func linkChip(_ title: String, kind: String) -> some View {
        HStack(spacing: Tokens.Space.s1) {
            Text(kind)
                .font(Typography.mono(10))
                .foregroundStyle(Tokens.Ink.soft)
            Text(title)
                .font(Typography.mono(12))
                .foregroundStyle(Tokens.Ink.primary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Tokens.Space.s3)
        .background(Capsule().fill(Tokens.Ground.card))
        .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair))
    }
}
