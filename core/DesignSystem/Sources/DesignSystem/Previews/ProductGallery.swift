import SwiftUI

/// Stand-in for a background-removed product cutout until real photos land.
private struct MockBottle: View {
    var tint: Color
    var height: CGFloat = 52

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(tint)
            .frame(width: height * 0.42, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin)
            )
    }
}

#Preview("product — avatar, rank badge, cards") {
    ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Space.s5) {
            HStack(spacing: Tokens.Space.s4) {
                Avatar(name: "maya", toneHex: "D9A87E", size: 58)
                RankBadge(rank: 2, outOf: 5, categoryLabel: "blushes")
            }

            Text("ANCHOR ITEM · FIT LOGGED").eyebrow()
            ProductCard(
                meta: .init(
                    brand: "fenty beauty",
                    name: "pro filt'r soft matte",
                    variant: "240 · 32ml",
                    benefitLine: "your anchor shade. holds all day."
                ),
                chips: [Chip("lasted all day", kind: .like, size: .sm, count: "×132")],
                fitLabel: "just right"
            ) { MockBottle(tint: Color(hex: 0xD9A87E), height: 60) }

            Text("ANCHOR ITEM · FIT MISSING").eyebrow()
            ProductCard(
                meta: .init(brand: "kosas", name: "revealer", variant: "6.5 n"),
                chips: [Chip("ran light", kind: .dislike, size: .sm, count: "×9")],
                needsFit: true
            ) { MockBottle(tint: Color(hex: 0xE5C6A8)) }

            Text("PERSONAL SCOPE").eyebrow()
            ProductCard(
                meta: .init(
                    brand: "the shelf lab",
                    name: "flaxseed curl gel",
                    variant: "250ml · homemade",
                    benefitLine: "yours until three people log it"
                ),
                isPersonalScope: true
            ) { MockBottle(tint: Color(hex: 0xE7E2D6)) }
        }
        .padding(Tokens.Space.s5)
    }
    .background(Tokens.Ground.milk)
    .task { Typography.registerFonts() }
}
