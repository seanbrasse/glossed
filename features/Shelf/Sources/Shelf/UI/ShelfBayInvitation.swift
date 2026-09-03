import DesignSystem
import SwiftUI

// The empty shelf's one tier, and what stands on it. Sean, Sep 2: *"0 products
// should still be 1 tier and encourage users to add to their shelf."* So the
// plank is not bare: a dashed slot with a `+` stands where the first product
// will, the line beside it says what to do, and the whole tier is the door.
// The first product then lands on this same tier — the bay is the category's
// from then on — rather than replacing a drawing with a different one.

extension ShelfBayView {
    /// One plank between the uprights with the invitation standing on it.
    /// `onAdd` opens the add-ladder; nil (fixtures, previews) draws the same
    /// tier untappable rather than a door onto nothing.
    public static func bare(onAdd: (() -> Void)? = nil) -> ShelfBayView {
        ShelfBayView(bare: true, onAdd: onAdd)
    }

    @ViewBuilder var invitation: some View {
        if let onAdd {
            Button(action: onAdd) { invitationLabel }
                .buttonStyle(.plain)
                .accessibilityLabel("add your first product")
        } else {
            invitationLabel
        }
    }

    /// The slot is drawn the way the ladder draws its "none of these" glyph —
    /// a dashed outline, the kit's mark for a place something can go — at the
    /// height a small product would stand.
    private var invitationLabel: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s3) {
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(
                    Tokens.Ink.primary, style: StrokeStyle(lineWidth: Tokens.Border.thin, dash: [4, 3])
                )
                .frame(width: 40, height: 52)
                .overlay(PlusIcon(size: 18).foregroundStyle(Tokens.Ink.primary))
            Text("add your first product")
                .font(Typography.mono(11.5))
                .foregroundStyle(Tokens.Ink.primary)
                // The label's own trick (GLO-149): a milk ground so the
                // uprights behind the bay do not cut through the words.
                .padding(.horizontal, 5)
                .background(Tokens.Ground.milk)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        // Where the first product will stand: past the left upright, at the
        // label's own leading edge, not on the plank's bare margin.
        .padding(.leading, Frame.labelLeading - Frame.bayHorizontalPadding)
        .padding(.bottom, Tokens.Space.s1)
        // The whole tier answers, not the dashes: a `.plain` button
        // hit-tests its label's opaque content (#500, #513).
        .contentShape(Rectangle())
    }
}
