import DesignSystem
import SwiftUI

/// The look composer (GLO-199). No kit frame exists — the `G.Feed` frame is
/// stale and has no composer — so this is built from the design system per
/// the standing no-frames ruling, and Sean workshops it in the PR.
///
/// The one pop moment is the post button. Everything else stays quiet: the
/// photo is the content, and the chrome should not compete with it.
public struct ComposerView: View {
    @State private var model: ComposerModel
    @State private var pickingTagFor: UUID?
    private let onPickPhoto: (() -> Void)?
    private let onSaved: (UUID) -> Void
    private let onClose: () -> Void

    public init(
        model: ComposerModel,
        onPickPhoto: (() -> Void)? = nil,
        onSaved: @escaping (UUID) -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.onPickPhoto = onPickPhoto
        self.onSaved = onSaved
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                header
                photoStrip
                if !model.photos.isEmpty {
                    tagSection
                }
                GlossedTextArea(text: $model.caption, label: "caption · optional")
                honestyLine
                if let failure = model.saveFailure {
                    failureRow(failure)
                }
                postRow
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .onChange(of: model.phase) { _, phase in
            if case let .saved(id) = phase {
                onSaved(id)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("new look")
                .font(Typography.display(30))
                .foregroundStyle(Tokens.Ink.primary)
            Spacer(minLength: 0)
            Button("close") { onClose() }
                .buttonStyle(.glossed(.secondary, size: .sm))
        }
    }

    /// The photos, plus the add tile while there is room. The cap is the
    /// model's; when it is reached the tile is absent rather than disabled —
    /// an affordance that cannot act is not offered.
    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s3) {
                ForEach(model.photos) { photo in
                    photoTile(photo)
                }
                if model.canAddPhoto, let onPickPhoto {
                    Button(action: onPickPhoto) {
                        VStack(spacing: Tokens.Space.s2) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 22, weight: .medium))
                            Text(model.photos.isEmpty ? "add a photo" : "another")
                                .font(Typography.mono(11))
                        }
                        .foregroundStyle(Tokens.Ink.primary)
                        .frame(width: 104, height: 132)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                                .strokeBorder(
                                    Tokens.Ink.primary,
                                    style: StrokeStyle(lineWidth: Tokens.Border.thin, dash: [5, 4])
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("add a photo")
                }
            }
        }
    }

    private func photoTile(_ photo: ComposerPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                #if canImport(UIKit)
                    if let image = UIImage(data: photo.localData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(Tokens.Support.lilacSoft)
                    }
                #else
                    // macOS test builds never render this; the tile ground
                    // stands in so the package still compiles there.
                    Rectangle().fill(Tokens.Support.lilacSoft)
                #endif
            }
            .frame(width: 104, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
            )

            Button {
                model.removePhoto(photo.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Tokens.Ink.primary)
                    .padding(6)
                    .background(Tokens.Ground.milk, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("remove this photo")
        }
    }

    /// Tags list as rows, not pins-on-photo yet: pin placement needs the
    /// full-size photo canvas, which is the next slice of this ticket. The
    /// data model already carries (x, y), so the canvas changes no store.
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("TAGGED FROM YOUR SHELF").eyebrow()
            ForEach(model.tags) { tag in
                HStack {
                    Text(tag.label)
                        .font(Typography.display(14, weight: 700))
                        .foregroundStyle(Tokens.Ink.primary)
                    Spacer(minLength: 0)
                    Button("untag") { model.removeTag(tag.variantID) }
                        .buttonStyle(.plain)
                        .font(Typography.mono(11))
                        .foregroundStyle(Tokens.Cherry.deep)
                }
            }
            if model.tags.isEmpty {
                Text("tap tag to name what you're wearing — shade and all.")
                    .meta()
            }
        }
    }

    /// True today, and it must change the day moderation lands: drafts are
    /// visible only to their owner, and no copy promises a review that is
    /// not built (GLO-189).
    private var honestyLine: some View {
        Text("saves to your account. nothing shows it to anyone yet — the public feed isn't built.")
            .meta()
    }

    private func failureRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text(message).meta()
            Button("try again") { model.post() }
                .buttonStyle(.glossed(.secondary, size: .sm))
        }
    }

    private var postRow: some View {
        Button(model.phase == .saving ? "saving…" : "save look") {
            model.post()
        }
        .buttonStyle(.glossed(block: true))
        .disabled(!model.canPost)
    }
}
