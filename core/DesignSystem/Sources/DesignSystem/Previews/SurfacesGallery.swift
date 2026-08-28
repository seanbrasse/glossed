import SwiftUI

#Preview("surfaces — card, sheet, toast, icon button") {
    VStack(alignment: .leading, spacing: Tokens.Space.s5) {
        Text("RESTING · MOST OF A SCREEN").eyebrow()
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text("pocket blush").font(Typography.display(20))
                Text("the natural flush").meta()
            }
        }

        Text("ONE POP MOMENT · EVIDENCE").eyebrow()
        GlossedCard(tint: .mint, pop: true) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                EvidenceLine(n: 89, label: "people in your shade rated it", tone: .ink)
                ChipGroup([
                    Chip("dewy finish", kind: .attribute),
                    Chip("lasts on combo", kind: .like, count: "×89", rotation: Tokens.Rotate.r3)
                ])
            }
        }

        HStack(spacing: Tokens.Space.s3) {
            IconButton("gearshape", label: "settings") {}
            IconButton("plus", label: "add a product", pop: true) {}
            Toast("ranked! nice taste ✿", hand: true)
        }

        GlossedSheet {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text("what are we making?").font(Typography.display(19))
                Text("add · import · collection · routine").meta()
            }
        }
    }
    .padding(Tokens.Space.s5)
    .background(Tokens.Ground.milk)
    .task { Typography.registerFonts() }
}
