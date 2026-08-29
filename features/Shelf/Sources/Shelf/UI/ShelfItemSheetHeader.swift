import DataKit
import DesignSystem
import SwiftUI

// The sheet's grabber and header, split out because `ShelfItemSheet` reached
// SwiftLint's 300-line ceiling when the height bound arrived (GLO-160).
// Mechanical: no behaviour changed, and these two are the pieces with no
// dependency on the sheet's optional handlers, so the split falls on a seam
// rather than through the middle of one.

extension ShelfItemSheet {
    var grabber: some View {
        Capsule()
            .fill(Tokens.Ground.line)
            .frame(width: 44, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
            .accessibilityHidden(true)
    }

    var header: some View {
        HStack(alignment: .top, spacing: 14) {
            // Bigger than anywhere else and tilted: this is the one screen
            // where the object itself is the subject rather than a thumbnail.
            ProductImage(
                catalog: item.catalogImageURL,
                kind: item.packaging,
                tint: ProductMock.tint(for: item.name),
                scale: 82,
                rotation: .degrees(-3),
                label: item.brand
            )
            // The slot is as wide as the drawing scale, not as wide as the
            // drawing. A brand sticker is wider than the bottle it is stuck to
            // — that is what a label looks like — and without a reserved slot
            // it runs under the product name and makes the title unreadable.
            // Very long brands still overflow; capping the sticker itself
            // belongs in `ProductMock`, not here.
            .frame(width: 82)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.brand).eyebrow()
                Text(item.name)
                    .font(Typography.display(21))
                    .tracking(-0.42)
                    .foregroundStyle(Tokens.Ink.primary)
                    .padding(.top, 3)
                    .padding(.bottom, 2)
                Text(statusLine).meta()
                badges
                // The two icons on the product (GLO-87): saved / tried,
                // right where the object is the subject.
                if let onStatusChange {
                    ShelfTriedIcons(status: liveStatus, onChange: onStatusChange)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            closeButton
        }
    }

    /// "joy · 7.5ml · week 3", and just the status when there is no variant —
    /// never a stray separator standing in for a size we do not have (GLO-63).
    private var statusLine: String {
        // The optimistic status wins, so the header agrees with the icons
        // the moment one is tapped (salvaged from #157).
        let label = (status != nil && status != item.status)
            ? ShelfItem.label(for: liveStatus) : item.statusLabel()
        return [item.variant, label]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private var badges: some View {
        HStack(spacing: 6) {
            // Rank is always relative and always says of-what. A bare "#2" is
            // the star rating this product does not have.
            if let rank = item.rank, rankedInCategory > 0 {
                Badge("#\(rank) of \(rankedInCategory)", tone: .cherry)
            }
            if item.isPersonalScope {
                Badge("yours only", tone: .lilac)
            }
        }
        .padding(.top, 7)
    }
}
