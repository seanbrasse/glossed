import DesignSystem
import SwiftUI

/// The default want-to-try collection's card (Sean, Aug 31 batch 2): "a
/// save icon on it, and a grid of 4 saved products with our colors behind
/// each product." Leads the collections tab; always present when the store
/// is wired — a DEFAULT collection exists even empty, and the empty card
/// says what lands here.
struct WantToTryCard: View {
    let entries: [WantToTryEntry]

    /// The kit's four soft fills, rotating behind the cutouts — "our
    /// colors," by index so the grid reads as deliberate, not random.
    private static let tints: [Color] = [
        Tokens.Support.mintSoft, Tokens.Support.lilacSoft,
        Tokens.Support.butterSoft, Tokens.Cherry.soft
    ]

    var body: some View {
        GlossedCard(padding: Tokens.Space.s3) {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                grid
                HStack(spacing: Tokens.Space.s2) {
                    SaveIcon(size: 15)
                        .foregroundStyle(Tokens.Ink.primary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("want to try")
                            .font(Typography.display(Typography.Size.body))
                            .foregroundStyle(Tokens.Ink.primary)
                        Text(line).meta()
                    }
                }
            }
        }
    }

    private var line: String {
        entries.isEmpty
            ? "save products and they land here"
            : "\(entries.count) \(entries.count == 1 ? "product" : "products")"
    }

    /// 2×2, the first four. Each cell: a soft tint with the product's
    /// catalog cutout over it; a missing image leaves the tint, which is
    /// less, never wrong. Empty slots stay tinted so the card is the same
    /// shape at every count.
    private var grid: some View {
        let cells: [WantToTryEntry?] = (0 ..< 4).map { entries.indices.contains($0) ? entries[$0] : nil }
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Tokens.Space.s1), GridItem(.flexible())],
            spacing: Tokens.Space.s1
        ) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, entry in
                cell(entry, tint: Self.tints[index % Self.tints.count])
            }
        }
    }

    private func cell(_ entry: WantToTryEntry?, tint: Color) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    tint
                    if let url = entry?.imageURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit().padding(Tokens.Space.s1)
                        } placeholder: {
                            Color.clear
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }
}
