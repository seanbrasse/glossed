import SwiftUI

#Preview("product mock — the drawn product, one shape per packaging") {
    VStack(alignment: .leading, spacing: Tokens.Space.s5) {
        Text("EVERY KIND THE KIT DRAWS").eyebrow()
        HStack(alignment: .bottom, spacing: Tokens.Space.s4) {
            ForEach(ProductMock.Kind.allCases, id: \.self) { kind in
                VStack(spacing: Tokens.Space.s2) {
                    ProductMock(kind: kind, tint: ProductMock.tint(for: kind.rawValue), scale: 62)
                    Text(kind.rawValue).meta()
                }
            }
        }
        Text("AT ROW SCALE · THE LADDER DRAWS THESE AT 50").eyebrow()
        HStack(alignment: .bottom, spacing: Tokens.Space.s4) {
            ForEach(ProductMock.Kind.allCases, id: \.self) { kind in
                ProductMock(kind: kind, tint: ProductMock.tint(for: kind.rawValue), scale: 50)
                    .frame(width: 46)
            }
        }
    }
    .padding(Tokens.Space.s5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Tokens.Ground.milk)
    .task { Typography.registerFonts() }
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
            ) { ProductMock(kind: .bottle, tint: ProductMock.tint(for: "foundation"), scale: 60) }

            Text("ANCHOR ITEM · FIT MISSING").eyebrow()
            ProductCard(
                meta: .init(brand: "kosas", name: "revealer", variant: "6.5 n"),
                chips: [Chip("ran light", kind: .dislike, size: .sm, count: "×9")],
                needsFit: true
            ) { ProductMock(kind: .dropper, tint: ProductMock.tint(for: "concealer"), scale: 52) }

            Text("PERSONAL SCOPE").eyebrow()
            ProductCard(
                meta: .init(
                    brand: "the shelf lab",
                    name: "flaxseed curl gel",
                    variant: "250ml · homemade",
                    benefitLine: "yours until three people log it"
                ),
                isPersonalScope: true
            ) { ProductMock(kind: .jar, tint: ProductMock.tint(for: "styler"), scale: 52) }
        }
        .padding(Tokens.Space.s5)
    }
    .background(Tokens.Ground.milk)
    .task { Typography.registerFonts() }
}

#Preview("typographic tile — the floor of the fallback chain") {
    VStack(alignment: .leading, spacing: Tokens.Space.s5) {
        Text("NO PHOTO YET · NEVER A BROKEN IMAGE").eyebrow()
        HStack(spacing: Tokens.Space.s3) {
            TypographicTile(brand: "Rare Beauty", seed: "blush")
            TypographicTile(brand: "Glow Recipe", seed: "serum")
            TypographicTile(brand: "Glossier", seed: "lip-oil")
            TypographicTile(brand: "Drunk-Elephant", seed: "cleanser")
            TypographicTile(brand: "", seed: "mask")
        }
        Text("SAME SEED, SAME COLOUR, EVERY LAUNCH").eyebrow()
        ProductCard(
            meta: .init(brand: "rare beauty", name: "soft pinch liquid blush", variant: "joy"),
            isPersonalScope: true
        ) {
            TypographicTile(brand: "Rare Beauty", seed: "blush")
        }
    }
    .padding(Tokens.Space.s5)
    .background(Tokens.Ground.milk)
}
