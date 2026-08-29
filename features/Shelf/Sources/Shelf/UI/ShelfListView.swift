import DesignSystem
import SwiftUI

/// The shelf's other half — `G.Shelf`'s `view === 'list'` branch.
///
/// One collapsible card per category, each carrying its own count, opening onto
/// the products as rows. The bay view is for recognising a bottle; this is for
/// reading names, and it is the view that works when you own two hundred things
/// or when the drawings all look alike.
///
/// It is not a fallback. Both views render the same items in the same order —
/// the toggle changes what you can do with them, not what is true.
public struct ShelfListView: View {
    private let sections: [ShelfSection]
    private let openSection: String?
    private let onToggleSection: (String) -> Void
    private let onTapItem: (ShelfItem) -> Void

    public init(
        sections: [ShelfSection],
        openSection: String?,
        onToggleSection: @escaping (String) -> Void,
        onTapItem: @escaping (ShelfItem) -> Void = { _ in }
    ) {
        self.sections = sections
        self.openSection = openSection
        self.onToggleSection = onToggleSection
        self.onTapItem = onTapItem
    }

    public var body: some View {
        VStack(spacing: 10) {
            ForEach(sections, id: \.slug) { section in
                card(section)
            }
        }
        .padding(.top, 2)
    }

    private func card(_ section: ShelfSection) -> some View {
        VStack(spacing: 0) {
            header(section)
            if openSection == section.slug {
                VStack(spacing: 8) {
                    ForEach(section.items) { item in
                        row(item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
        )
    }

    private func header(_ section: ShelfSection) -> some View {
        Button { onToggleSection(section.slug) } label: {
            HStack(spacing: 10) {
                Text(section.label)
                    .font(Typography.display(16))
                    .tracking(-0.16)
                    .foregroundStyle(Tokens.Ink.primary)
                // The count is on the closed card too, which is the whole
                // reason to collapse one: you can see how much is in a category
                // without opening it.
                Text("\(section.items.count) items").meta()
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.Ink.soft)
                    .rotationEffect(.degrees(openSection == section.slug ? 180 : 0))
                    .animation(Tokens.Motion.pop(Tokens.Motion.med), value: openSection)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.label), \(section.items.count) items")
        .accessibilityAddTraits(openSection == section.slug ? [.isSelected] : [])
        .accessibilityHint(openSection == section.slug ? "collapses this category" : "expands this category")
    }

    /// The nested card gets `line-on-card` rather than `line` — a hairline tuned
    /// for the bone page reads as a smudge on white.
    ///
    /// It repaints `ProductCard`'s own border rather than replacing it, because
    /// the primitive takes no border argument. Same path, same width, opaque
    /// stroke, so the result is exactly the lighter line; if `ProductCard` ever
    /// grows a real override this should use it.
    private func row(_ item: ShelfItem) -> some View {
        ProductCard(
            meta: .init(brand: item.brand, name: item.name, variant: item.variant),
            onTap: { onTapItem(item) },
            thumb: {
                ProductImage(
                    catalog: item.catalogImageURL,
                    kind: item.packaging,
                    tint: ProductMock.tint(for: item.name),
                    scale: 52
                )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ground.lineOnCard, lineWidth: Tokens.Border.hair)
        )
        // GLO-100: same ghost the bay draws — an intention, not a bottle.
        .opacity(item.status == .wantToTry ? 0.35 : 1)
    }
}
