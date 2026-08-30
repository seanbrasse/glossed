import SwiftUI

#Preview("primitives — resting on bone") {
    ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Text("glossed*")
                .font(Typography.display(Typography.Size.h1))

            Text("THE SHEET · PRIMITIVES").eyebrow()

            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Button("rank it") {}.buttonStyle(.glossed(.primary))
                Button("leaderboard") {}.buttonStyle(.glossed(.secondary))
                Button("sign in with apple") {}.buttonStyle(.glossed(.ink, block: true))
                Button("following") {}.buttonStyle(.glossed(.mint, size: .sm))
                // GLO-76: the kit's disabled recipe — 45% on the whole
                // sticker, press ignored. Enabled and disabled side by side
                // is the whole check.
                Button("add to shelf") {}.buttonStyle(.glossed(.primary)).disabled(true)
            }

            ChipGroup([
                Chip("lasts on combo", kind: .like, count: "×89", rotation: Tokens.Rotate.r3),
                Chip("pilled under spf", kind: .dislike, rotation: Tokens.Rotate.r2),
                Chip("fragrance-free", kind: .attribute),
                Chip("purged then cleared", kind: .like, count: "×76", week: 9)
            ])

            HStack(spacing: Tokens.Space.s2) {
                Badge("#2 of 5", tone: .cherry)
                Badge("fenty 240", tone: .butter)
                Badge("3b", tone: .mint)
                PhaseTag(.v15)
            }

            EvidenceLine(n: 12, label: "people wear this exact shade")
            EvidenceLine(n: 3, of: 5, label: "matched outright")
            EvidenceLine(n: 2, label: "face-offs", empty: "not enough face-offs yet · 2 of 5")

            Text("FORMS").eyebrow()
            FormsPreviewRow()

            Text("no wrong answers ✿\u{FE0E}")
                .handAside()
                .rotationEffect(Tokens.Rotate.r3)
        }
        .padding(Tokens.Space.s5)
    }
    .background(Tokens.Ground.milk)
    .task { Typography.registerFonts() }
}

/// Stateful row so the preview exercises focus + selection.
private struct FormsPreviewRow: View {
    @State private var query = ""
    @State private var brand = "rare beauty"
    @State private var note = "one dot, blends forever"

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            GlossedInput("brand, product, shade…", text: $query, label: "search")
            GlossedSelect(
                options: ["rare beauty", "rhode", "fenty beauty", "kosas"],
                selection: $brand,
                label: "brand"
            )
            GlossedTextArea(text: $note, label: "note")
        }
    }
}
