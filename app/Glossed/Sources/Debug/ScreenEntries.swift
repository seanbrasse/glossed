#if DEBUG

    import DesignSystem
    import Shelf
    import SwiftUI

    @MainActor
    enum GalleryEntries {
        static let productMock = ScreenEntry(
            id: "ds-product-mock",
            title: "design system · ProductMock",
            note: "every kind at shelf heights on one ground line — a compact is visibly smaller than a bottle"
        ) {
            ProductMockGallery()
        }

        private struct ProductMockGallery: View {
            var body: some View {
                VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                    Text("EVERY KIND · SHELF HEIGHTS · RANK STICKER").eyebrow()
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array(ProductMock.Kind.allCases.enumerated()), id: \.element) { index, kind in
                            ProductMock(
                                kind: kind,
                                tint: ProductMock.tint(for: kind.rawValue),
                                scale: ShelfItem.kitScale(kind),
                                rotation: .degrees([-2, 1.5, -1, 2, -1.5][index % 5]),
                                label: "#\(index + 1)"
                            )
                        }
                    }
                    Rectangle()
                        .fill(Tokens.Support.butterSoft)
                        .frame(height: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
                        )
                    Spacer(minLength: 0)
                }
                .padding(Tokens.Space.s5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Tokens.Ground.milk)
            }
        }
    }
#endif
