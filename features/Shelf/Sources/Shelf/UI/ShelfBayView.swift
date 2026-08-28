import DesignSystem
import SwiftUI

/// The shelf itself — `G.Shelf`'s `view === 'shelf'` branch.
///
/// Not a grid of cards. Three uprights run the full height behind everything;
/// each bay is a row of objects standing on a ground line, bottom-aligned so
/// they share it; the category name floats over the shelf on a chip of the page
/// colour, the way a label sits on the edge of a real shelf.
///
/// The bottom alignment is the whole trick. Objects drawn at different heights
/// and hung from a common top read as a chart; standing on a common floor they
/// read as your bathroom counter.
public struct ShelfBayView: View {
    private let bays: [ShelfBay]
    private let onTap: (ShelfItem) -> Void

    public init(bays: [ShelfBay], onTap: @escaping (ShelfItem) -> Void = { _ in }) {
        self.bays = bays
        self.onTap = onTap
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(bays) { bay in
                bayRow(bay)
            }
        }
        .background(alignment: .topLeading) { uprights }
        .padding(.top, 4)
    }

    // MARK: - The frame's numbers, named once

    private enum Frame {
        static let upright: CGFloat = 11
        static let uprightInsetFromEdge: CGFloat = 14
        /// The uprights stop short of the stack at both ends so they read as
        /// standing behind the shelves rather than framing them.
        static let uprightTopInset: CGFloat = 8
        static let uprightBottomInset: CGFloat = 10

        static let bayMinHeight: CGFloat = 82
        static let bayHorizontalPadding: CGFloat = 14
        static let bayBottomPadding: CGFloat = 3
        static let itemGap: CGFloat = 10

        static let groundHeight: CGFloat = 10
        /// The ground line bleeds past the bay on both sides, so a shelf looks
        /// wider than the things standing on it.
        static let groundBleed: CGFloat = 4
        static let gapBetweenBays: CGFloat = 10

        static let labelLeading: CGFloat = 34
        static let labelTop: CGFloat = 3

        /// Every fifth object repeats a tilt. Nothing on a real shelf is
        /// perfectly straight, and a fixed cycle keeps it from re-shuffling on
        /// every redraw — which would read as a rendering bug.
        static let tilts: [Double] = [-2, 1.5, -1, 2, -1.5]
    }

    // MARK: - Pieces

    private func bayRow(_ bay: ShelfBay) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: Frame.itemGap) {
                ForEach(Array(bay.items.enumerated()), id: \.element.id) { index, item in
                    Button { onTap(item) } label: {
                        ProductMock(
                            kind: item.packaging,
                            tint: ProductMock.tint(for: item.name),
                            scale: item.drawnScale,
                            rotation: .degrees(Frame.tilts[index % Frame.tilts.count]),
                            label: item.rank.map { "#\($0)" }
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.brand.lowercased()), \(item.name.lowercased())")
                    .accessibilityHint("opens this item")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Frame.bayHorizontalPadding)
            .padding(.bottom, Frame.bayBottomPadding)
            .frame(maxWidth: .infinity, minHeight: Frame.bayMinHeight, alignment: .bottomLeading)

            ground
            Color.clear.frame(height: Frame.gapBetweenBays)
        }
        .overlay(alignment: .topLeading) { label(bay.label) }
    }

    /// A hard 2pt line-coloured edge under the shelf rather than a blur — the
    /// system's shadows are offsets with no blur, everywhere.
    ///
    /// The bleed is negative horizontal padding, which is safe here and worth
    /// saying why: the ground is the widest thing in the stack, so if negative
    /// padding grew its reported size it would widen the whole shelf and push
    /// the uprights off their insets. It does not — the padding view proposes
    /// `width + 8` to a flexible shape and still reports `width` — so the line
    /// overhangs without moving anything. Verified on a simulator against the
    /// upright insets.
    private var ground: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Tokens.Support.butterSoft)
            .frame(height: Frame.groundHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
            )
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Tokens.Ground.line)
                    .offset(y: 2)
            )
            .padding(.horizontal, -Frame.groundBleed)
    }

    /// Sits on a chip of the page colour so the shelf appears to pass behind
    /// it. Not tappable: it names the bay, it is not a way into anything.
    private func label(_ text: String) -> some View {
        Text(text)
            .font(Typography.mono(10.5))
            .kerning(10.5 * 0.16)
            .textCase(.uppercase)
            .foregroundStyle(Tokens.Ink.soft)
            .padding(.horizontal, 5)
            .background(Tokens.Ground.milk)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.leading, Frame.labelLeading)
            .padding(.top, Frame.labelTop)
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isHeader)
    }

    /// Three of them, running the full height behind the bays.
    private var uprights: some View {
        GeometryReader { geo in
            ForEach(Array(ShelfBayView.uprightOffsets(in: geo.size.width).enumerated()), id: \.offset) { _, x in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Tokens.Support.butterSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
                    )
                    .frame(
                        width: Frame.upright,
                        height: max(0, geo.size.height - Frame.uprightTopInset - Frame.uprightBottomInset)
                    )
                    .offset(x: x, y: Frame.uprightTopInset)
            }
        }
        .accessibilityHidden(true)
    }

    /// Leading offsets for the three uprights: inset from each edge, and one
    /// centred. Returned rather than positioned inline so the arithmetic can be
    /// checked without rendering — a centre rail that is not centred is the kind
    /// of thing that looks almost right in a screenshot.
    static func uprightOffsets(in width: CGFloat) -> [CGFloat] {
        [
            Frame.uprightInsetFromEdge,
            width / 2 - Frame.upright / 2,
            width - Frame.uprightInsetFromEdge - Frame.upright
        ]
    }
}
