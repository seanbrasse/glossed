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
    private let sections: [ShelfSection]
    private let onTap: (ShelfItem) -> Void

    /// The shelf's own width, once the layout has told us. Zero means "not yet":
    /// packing needs a real number, and guessing one lays the shelf out twice,
    /// visibly.
    @State private var shelfWidth: CGFloat = 0

    /// Set, this view draws one bare tier under that label and nothing else —
    /// the empty shelf's own shelf. `ShelfBayInvitation.swift` is what stands on it.
    let bareLabel: String?
    /// The empty tier's door: opens the add-ladder. Nil in fixtures.
    let onAdd: (() -> Void)?

    public init(sections: [ShelfSection], onTap: @escaping (ShelfItem) -> Void = { _ in }) {
        self.sections = sections
        self.onTap = onTap
        bareLabel = nil
        onAdd = nil
    }

    init(bareLabel: String, onAdd: (() -> Void)?) {
        sections = []
        onTap = { _ in }
        self.bareLabel = bareLabel
        self.onAdd = onAdd
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(bays) { bay in
                bayRow(bay)
            }
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .topLeading) { uprights }
        .background { widthReader }
        .padding(.top, 4)
        // Air either side of the whole unit — uprights, planks and bleed all
        // move in together, and the width reader measures the narrowed shelf
        // so the packing agrees with what is drawn (GLO-155, Sean's call).
        .padding(.horizontal, Frame.shelfInset)
    }

    /// How many fit is a question about the shelf, so it is answered here rather
    /// than in the model — `ShelfModel` decides *which* items and in what order,
    /// which is the part that should be testable without a layout.
    private var bays: [ShelfBay] {
        if let bareLabel {
            return [ShelfBay(id: ShelfBay.bare.id, label: bareLabel, items: [])]
        }
        guard shelfWidth > 0 else { return [] }
        return ShelfBay.bays(from: sections, fittingWidth: shelfWidth - Frame.bayHorizontalPadding * 2)
    }

    /// Reads the width the parent handed down.
    ///
    /// Not circular, which is why this is safe: the stack's width comes from its
    /// parent (`maxWidth: .infinity`) and never from the bays, so measuring it
    /// cannot depend on what the measurement decides. Height is content-driven
    /// and is not read here.
    private var widthReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { shelfWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, width in shelfWidth = width }
        }
    }

    // MARK: - The frame's numbers, named once

    enum Frame {
        static let upright: CGFloat = 11
        static let uprightInsetFromEdge: CGFloat = 14
        /// The uprights stop short of the stack at both ends so they read as
        /// standing behind the shelves rather than framing them.
        static let uprightTopInset: CGFloat = 8
        static let uprightBottomInset: CGFloat = 10

        static let bayMinHeight: CGFloat = 77
        /// Inset on each side of the shelf, inside the page's own 16pt
        /// margin. The shelf is an object in a room, not a thing bolted to
        /// the screen edges.
        static let shelfInset: CGFloat = 12
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
        /// The band the label owns at the top of every bay (GLO-149). Sized to
        /// the chip — 10.5pt mono plus its padding — with air under it.
        static let labelBand: CGFloat = 18

        /// The kit's five tilts. Nothing on a real shelf is perfectly straight.
        static let tilts: [Double] = [-2, 1.5, -1, 2, -1.5]
    }

    // MARK: - Pieces

    private func bayRow(_ bay: ShelfBay) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: Frame.itemGap) {
                if isBare {
                    invitation
                }
                ForEach(bay.items) { item in
                    Button { onTap(item) } label: {
                        ProductImage(
                            catalog: item.catalogImageURL,
                            kind: item.packaging,
                            tint: ProductMock.tint(for: item.name),
                            scale: item.drawnScale,
                            // The bucket's own cap (GLO-82): render and slot
                            // agree, and no photo outgrows its size class.
                            maxWidth: item.sizeClass.maxWidth,
                            rotation: .degrees(ShelfBayView.tilt(for: item)),
                            label: item.rank.map { "#\($0)" }
                        )
                        // Rendered into the same slot the packing reserved. A
                        // mock narrower than the floor would otherwise be laid
                        // out at its drawn width, which leaves the shelf short
                        // of full *and* puts the rank stickers back within
                        // touching distance — the two things the floor exists
                        // to prevent.
                        .frame(width: item.slotWidth)
                        // The contact shadow: a soft pool where the object
                        // meets the plank, which is what makes it *stand on*
                        // the shelf rather than float near it (Sean's
                        // session-5 review — commit to the shelf).
                        .background(alignment: .bottom) {
                            Ellipse()
                                .fill(Tokens.Ink.primary.opacity(0.14))
                                .frame(width: item.slotWidth * 0.72, height: 5)
                                .offset(y: 3)
                        }
                        // GLO-100: a want-to-try is an intention, not a
                        // bottle — it stands on the shelf ghosted, never
                        // as owned.
                        .opacity(item.status == .wantToTry ? 0.35 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.brand.lowercased()), \(item.name.lowercased())")
                    .accessibilityHint("opens this item")
                }
            }
            // Left on the plank, per the kit. Session 5 centred this (one
            // object mid-shelf "reads as placed"); Sean reversed it in
            // session 7 — a lone item belongs at the start of its shelf.
            // The old centring's other worry — the first item standing on
            // the left upright — was never centring's to solve: a full bay
            // already spans the padded width and overlaps both uprights.
            .padding(.horizontal, Frame.bayHorizontalPadding)
            .padding(.bottom, Frame.bayBottomPadding)
            // The band the label owns, taken out of the bay rather than added
            // to it: the bay is the height it always was, and the items are
            // capped to what is left. Growing the bay instead would have cost
            // roughly one shelf per screen.
            .frame(
                maxWidth: .infinity,
                minHeight: Frame.bayMinHeight - Frame.labelBand,
                alignment: .bottomLeading
            )
            .padding(.top, Frame.labelBand)

            ground
            Color.clear.frame(height: Frame.gapBetweenBays)
        }
        .overlay(alignment: .topLeading) {
            // A bare bay has no label to hang; an empty pill would still
            // draw its milk ground on the plank.
            if !bay.label.isEmpty {
                label(bay.label)
            }
        }
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

    /// The tallest anything on a shelf may draw: what is left of the bay once
    /// the label has its band and the items have their footing. Nothing reads
    /// this at render time — `ShelfSizeClass.height` carries the real numbers,
    /// because the drawn height is also the packing width's input and both
    /// have to be constants. This is the number those must not exceed, and a
    /// test says so out loud (GLO-149).
    static let itemHeightCap: CGFloat = Frame.bayMinHeight - Frame.labelBand - Frame.bayBottomPadding

    /// Which way this object leans.
    ///
    /// Seeded on the product rather than on its position in the bay. The kit
    /// indexes the cycle by position, which was invisible while a bay held five
    /// — exactly one turn of a five-value cycle. Bays now hold as many as fit,
    /// so a positional cycle repeats twice across one shelf and reads as a
    /// pattern rather than as objects someone put down.
    ///
    /// Seeded, not random: a shelf that re-tilted itself on every redraw would
    /// read as a rendering bug. Same reasoning as `ProductMock.tintIndex`, and
    /// seeded on the name for the same reason — ids are random in fixtures, and
    /// a screenshot has to be reproducible.
    static func tilt(for item: ShelfItem) -> Double {
        Frame.tilts[ProductMock.tintIndex(for: item.name + item.categorySlug) % Frame.tilts.count]
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
