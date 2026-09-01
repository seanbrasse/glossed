import DesignSystem
import SwiftUI

// The tagged-product list under the photos, lifted out of `LookPostView.swift`
// when Sean's "products tagged in the look should be in an expandable tab"
// took that file past SwiftLint's 300-line ceiling.

extension LookPostView {
    @ViewBuilder var listing: some View {
        if state.hasTags {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                listingHeader
                if isListingOpen {
                    ForEach(state.listing) { group in
                        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                            Text(group.category.label).meta()
                            ForEach(group.entries) { entry in
                                listingRow(entry)
                            }
                        }
                    }
                }
            }
        }
    }

    func listingRow(_ entry: LookTagListingEntry) -> some View {
        Button {
            withAnimation(Tokens.Motion.pop(Tokens.Motion.med)) {
                _ = state.reveal(entry.product.variantID)
            }
        } label: {
            HStack(spacing: Tokens.Space.s2) {
                Text(entry.product.label)
                    .font(Typography.display(Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.primary)
                Spacer(minLength: 0)
                EyeIcon(size: 15)
                    .foregroundStyle(Tokens.Ink.soft)
            }
            .padding(.vertical, Tokens.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.product.label) — show its tag on the photo")
    }

    /// The accordion header. Follows `ShelfListView`'s shape, which is the
    /// house's only other collapsible: label, the count on the CLOSED card,
    /// and a chevron that rotates rather than swaps glyph.
    ///
    /// **The count is on the closed header on purpose.** Collapsing a section
    /// whose header does not say how much is inside makes the control a
    /// guess — the shelf learned that and the comment there says so.
    var listingHeader: some View {
        Button {
            withAnimation(Tokens.Motion.pop(Tokens.Motion.med)) {
                isListingOpen.toggle()
            }
        } label: {
            HStack(spacing: Tokens.Space.s2) {
                Text("TAGGED IN THIS LOOK").eyebrow()
                Text("\(state.taggedProductCount)").meta()
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.Ink.soft)
                    .rotationEffect(.degrees(isListingOpen ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("tagged in this look, \(state.taggedProductCount) products")
        .accessibilityAddTraits(isListingOpen ? [.isSelected] : [])
        .accessibilityHint(isListingOpen ? "collapses the list" : "expands the list")
    }
}
