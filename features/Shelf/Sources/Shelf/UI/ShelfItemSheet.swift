import DesignSystem
import SwiftUI

/// One item, opened from either view — the `sheet` branch of `G.Shelf`.
///
/// A sheet rather than a push, which is the app's habit and not an accident:
/// the shelf stays visible behind it, so the thing you are reading about is
/// still in the row you tapped. Coming back is a dismissal, not a navigation.
public struct ShelfItemSheet: View {
    private let item: ShelfItem
    /// How many products in this category carry a rank. The badge is `#2 of 5`
    /// and both halves have to come from the same place, or a shelf says you
    /// are second of five while showing you three things.
    private let rankedInCategory: Int
    private let onClose: () -> Void
    private let onRank: () -> Void
    private let onOpenProduct: () -> Void

    public init(
        item: ShelfItem,
        rankedInCategory: Int,
        onClose: @escaping () -> Void,
        onRank: @escaping () -> Void = {},
        onOpenProduct: @escaping () -> Void = {}
    ) {
        self.item = item
        self.rankedInCategory = rankedInCategory
        self.onClose = onClose
        self.onRank = onRank
        self.onOpenProduct = onOpenProduct
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            scrim
            sheet
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
    }

    /// Tapping outside closes. The kit's scrim is `rgba(27,25,23,.45)` — ink at
    /// 45%, not black, so the page underneath stays warm rather than going grey.
    private var scrim: some View {
        Button(action: onClose) {
            Rectangle()
                .fill(Tokens.Ink.primary.opacity(0.45))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("close")
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            grabber
            header
            if let benefit = item.benefitLine {
                Text(benefit)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(Tokens.Ink.primary)
                    .padding(.top, 12)
            }
            actions
        }
        .padding(.top, 12)
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
        // The sheet's background runs to the very bottom of the screen, but its
        // buttons must not: without this the primary action sits under the home
        // indicator, which eats the bottom of its tap target.
        .safeAreaPadding(.bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Ground.card)
        .clipShape(.rect(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        }
        // The sticker shadow points *up* here — the sheet is rising off the
        // page rather than resting on it.
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Tokens.Ink.primary)
                .offset(y: -3)
        )
        .transition(.move(edge: .bottom))
    }

    private var grabber: some View {
        Capsule()
            .fill(Tokens.Ground.line)
            .frame(width: 44, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            // Bigger than anywhere else and tilted: this is the one screen
            // where the object itself is the subject rather than a thumbnail.
            ProductMock(
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            closeButton
        }
    }

    /// "joy · 7.5ml · week 3", and just the status when there is no variant —
    /// never a stray separator standing in for a size we do not have (GLO-63).
    private var statusLine: String {
        [item.variant, item.statusLabel()]
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

    private var closeButton: some View {
        Button(action: onClose) {
            Text("×")
                .font(Typography.mono(16))
                .foregroundStyle(Tokens.Ink.soft)
                .frame(width: Tokens.hitTarget, height: Tokens.hitTarget, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("close")
    }

    /// "rank it" is the primary action on every item, which is the product's
    /// whole argument: a shelf is only worth having if it is ordered.
    private var actions: some View {
        HStack(spacing: 10) {
            Button("rank it", action: onRank)
                .buttonStyle(.glossed(block: true))
                .frame(maxWidth: .infinity)
            Button("full page", action: onOpenProduct)
                .buttonStyle(.glossed(.secondary))
                .fixedSize()
        }
        .padding(.top, 16)
    }
}
