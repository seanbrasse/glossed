import DesignSystem
import SwiftUI

// The empty shelf's one tier, and what stands on it. Sean, Sep 2: *"0 products
// should still be 1 tier and encourage users to add to their shelf"* — and
// then *"let's consolidate"*: this tier is the screen's one door to the
// ladder (the nav's `+` is the other, everywhere). A dashed slot with a `+`
// stands where the first product will; the words sit in the label band. The
// first product then lands on this same tier — the bay is the category's
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
    /// height a small product would stand. No words on the plank: they crossed
    /// the uprights; the bay's label band carries them instead. The whole
    /// tier answers a tap, not just the dashes.
    private var invitationLabel: some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.md)
            .strokeBorder(
                Tokens.Ink.primary, style: StrokeStyle(lineWidth: Tokens.Border.thin, dash: [4, 3])
            )
            .frame(width: 40, height: 52)
            .overlay(PlusIcon(size: 18).foregroundStyle(Tokens.Ink.primary))
            // Where the first product will stand: past the left upright, at
            // the label's own leading edge, not on the plank's bare margin.
            .padding(.leading, Frame.labelLeading - Frame.bayHorizontalPadding)
            .padding(.bottom, Tokens.Space.s1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}
