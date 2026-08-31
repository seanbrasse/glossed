import DesignSystem
import SwiftUI

/// The composer's tagging half (GLO-266). Its own file for the reason
/// `AppShellLooks` and `ComposerTagSection`'s siblings are: `ComposerView`
/// sits near SwiftLint's 300-line ceiling and the house remedy is to extract.
///
/// One photo at a time, full width, because the strip's 104pt tiles are far
/// too small to place a tag on — you cannot aim a thumb at a lip inside a
/// thumbnail. The strip stays the way you *choose* a photo; this is where you
/// tag it.
///
/// Below the canvas, "a list of tagged products, ordered by category" — and
/// tapping a row selects the photo that product is tagged on, which is the
/// composer's half of Sean's cross-photo sentence.
struct ComposerTagSection: View {
    @Bindable var model: ComposerModel
    let search: LookTagSearch
    @Binding var photoID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("TAG WHAT YOU'RE WEARING").eyebrow()
            if let photo = current {
                LookTagCanvas(board: $model.tagBoard, photoID: photo.id, search: search) {
                    image(photo)
                }
                .id(photo.id)
            }
            listing
        }
    }

    private var current: ComposerPhoto? {
        photoID.flatMap { id in model.photos.first { $0.id == id } } ?? model.photos.first
    }

    /// The photo, full width and squared. Squared rather than aspect-fit
    /// because a normalized tag has to mean the same thing at every size, and
    /// a container whose aspect ratio changes with the image would move every
    /// dot on it.
    private func image(_ photo: ComposerPhoto) -> some View {
        Group {
            #if canImport(UIKit)
                if let uiImage = UIImage(data: photo.localData) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Tokens.Support.lilacSoft)
                }
            #else
                // macOS test builds never render this; the ground stands in so
                // the package still compiles there.
                Rectangle().fill(Tokens.Support.lilacSoft)
            #endif
        }
        .aspectRatio(1, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        )
    }

    @ViewBuilder private var listing: some View {
        if model.tagBoard.isEmpty {
            Text("tap the photo to name what you're wearing — shade and all.").meta()
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                // The kit's own heading, from `G.Feed`. Mono because it is a
                // count, and it counts THIS look's tags — a page indicator,
                // never a sample size (GLO-196).
                Text(model.tagBoard.listHeading)
                    .font(Typography.mono(11))
                    .foregroundStyle(Tokens.Ink.soft)
                ForEach(model.tagListing) { group in
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        Text(group.category.label.uppercased()).eyebrow()
                        ForEach(group.entries) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
    }

    private func row(_ entry: LookTagListingEntry) -> some View {
        let isElsewhere = entry.placement.photoID != current?.id
        return Button {
            photoID = entry.placement.photoID
        } label: {
            HStack(spacing: Tokens.Space.s3) {
                LookTagDot(isFilled: true)
                Text(entry.product.label)
                    .font(Typography.display(14, weight: 700))
                    .foregroundStyle(Tokens.Ink.primary)
                Spacer(minLength: 0)
                if isElsewhere {
                    // Only when it is somewhere else: on the photo you are
                    // already looking at, "show" would be a button that does
                    // nothing.
                    Text("on another photo")
                        .font(Typography.mono(11))
                        .foregroundStyle(Tokens.Ink.soft)
                }
            }
            .frame(minHeight: Tokens.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isElsewhere
                ? "\(entry.product.label), tagged on another photo — show it"
                : "\(entry.product.label), tagged on this photo"
        )
    }
}
