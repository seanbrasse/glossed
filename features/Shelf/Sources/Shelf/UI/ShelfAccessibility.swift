import DesignSystem
import SwiftUI

// GLO-172. The shelf's accessibility-size behaviour, kept out of `ShelfView`
// which is at SwiftLint's file-length ceiling.

extension ShelfView {
    /// Scrolls **only** at accessibility sizes.
    ///
    /// A `ScrollView` here unconditionally was tried and reverted (GLO-172):
    /// it repairs accessibility and clips the view toggle at the default size,
    /// because the row has always been quietly compressing to fit and a scroll
    /// view removes the pressure that made it. So the axis changes only where
    /// the row genuinely cannot fit.
    @ViewBuilder var controls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView(.horizontal, showsIndicators: false) {
                controlRow.padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        } else {
            controlRow
        }
    }

    /// Sort on the left, view toggle pinned right — the kit puts them on one
    /// row because they are the two things you change about the same list.
    var controlRow: some View {
        HStack(alignment: .center, spacing: 8) {
            sortPills
            wishlistToggle
            searchToggle
            viewToggle
        }
    }

    /// Want-to-try on the shelf (GLO-100, Sean's sketch — workshop at
    /// review): the bookmark is GLO-87's own icon for the status, off by
    /// default, and toggling it in ghosts the wishlist onto the bays.
    var wishlistToggle: some View {
        Button {
            model.showsWishlist.toggle()
        } label: {
            Image(systemName: model.showsWishlist ? "bookmark.fill" : "bookmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Tokens.Ink.primary)
                .frame(width: 34, height: 30)
                .background(model.showsWishlist ? Tokens.Cherry.soft : Tokens.Ground.card)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        model.showsWishlist ? Tokens.Ink.primary : Tokens.Ground.line,
                        lineWidth: model.showsWishlist ? Tokens.Border.std : Tokens.Border.hair
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("show your want-to-try list")
        .accessibilityAddTraits(model.showsWishlist ? [.isSelected] : [])
    }

    // Find-what-I-own (GLO-73), folded into the controls row so search reads
    // as one more way to narrow the same list — beside sort, not above the
    // shelf. No kit frame exists for it; workshop at review.

    /// Moved from `ShelfView.swift` at the 300-line ceiling (GLO-108's empty
    /// state gate took it to 305) — a mechanical move, beside the row it sits in.
    var sortPills: some View {
        HStack(spacing: 6) {
            ForEach(ShelfSort.allCases, id: \.self) { option in
                Button { model.sort = option } label: {
                    Text(option.rawValue)
                        .font(Typography.mono(10.5))
                        .kerning(10.5 * 0.06)
                        // A fourth control on the row must not squeeze
                        // "favorite" into "favor ite" — pills keep their
                        // words (GLO-100's toggle made the row tight).
                        .fixedSize()
                        .foregroundStyle(Tokens.Ink.primary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 11)
                        .background(model.sort == option ? Tokens.Cherry.soft : Tokens.Ground.card)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                model.sort == option ? Tokens.Ink.primary : Tokens.Ground.line,
                                lineWidth: model.sort == option ? Tokens.Border.std : Tokens.Border.hair
                            )
                        )
                        .background(
                            // The selected pill is the only one that lifts. Two
                            // raised pills in a row of three read as neither.
                            Capsule()
                                .fill(model.sort == option ? Tokens.Ink.primary : .clear)
                                .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("sort by \(option.rawValue)")
                .accessibilityAddTraits(model.sort == option ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }
}
