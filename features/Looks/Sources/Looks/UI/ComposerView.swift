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
    /// Which photo the tagging canvas is showing. Nil follows the first photo.
    @State private var taggingPhotoID: UUID?
    /// Which tile the current drag is over — the strip's only drag state.
    @State private var dropTargetID: UUID?
    private let onPickPhoto: (() -> Void)?
    /// What the tag picker searches. **Optional, and the tagging half is
    /// absent without it** — the composer's own rule, the same one the add
    /// tile follows: an affordance that cannot act is not offered. The scope
    /// is the app's to choose (GLO-266), so the app supplies this.
    private let search: LookTagSearch?
    private let onSaved: (UUID) -> Void
    private let onClose: () -> Void

    public init(
        model: ComposerModel,
        onPickPhoto: (() -> Void)? = nil,
        search: LookTagSearch? = nil,
        onSaved: @escaping (UUID) -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.onPickPhoto = onPickPhoto
        self.search = search
        self.onSaved = onSaved
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                header
                photoStrip
                if !model.photos.isEmpty, let search {
                    ComposerTagSection(
                        model: model, search: search, photoID: $taggingPhotoID
                    )
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
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            strip
            if model.photos.count > 1 {
                // Discoverability, not decoration: a long-press drag nobody
                // is told about is an affordance nobody finds.
                Text("hold a photo to move it — the first one leads the post.")
                    .meta()
            }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s3) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                    photoTile(photo, at: index)
                        .onTapGesture { taggingPhotoID = photo.id }
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

    /// A tile is both a drag source and a drop target: dragging one onto
    /// another gives the dragged photo that tile's place. Tile-level targets
    /// rather than one strip-wide target because the strip scrolls at the cap
    /// (six tiles overflow any phone) and a drop zone you cannot reach is not
    /// a drop zone — one hop at a time always works.
    private func photoTile(_ photo: ComposerPhoto, at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            photoImage(photo)
            removeButton(photo)
            if model.photos.count > 1 {
                ordinal(index)
            }
        }
        .frame(width: 104, height: 132)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(
                    Tokens.Cherry.base,
                    lineWidth: dropTargetID == photo.id ? Tokens.Border.std : 0
                )
        )
        .draggable(photo.id.uuidString)
        .dropDestination(for: String.self) { payload, _ in
            guard let dragged = payload.first.flatMap(UUID.init(uuidString:)) else { return false }
            model.movePhoto(dragged, to: index)
            return true
        } isTargeted: { targeted in
            // Only the tile that claimed the highlight may clear it —
            // otherwise the tile the drag just LEFT wipes the one it
            // arrived at, and the outline flickers off mid-drag.
            if targeted {
                dropTargetID = photo.id
            } else if dropTargetID == photo.id {
                dropTargetID = nil
            }
        }
    }

    private func photoImage(_ photo: ComposerPhoto) -> some View {
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
    }

    private func removeButton(_ photo: ComposerPhoto) -> some View {
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

    /// The order, said out loud, so a reorder has something to confirm it.
    /// Mono because it is a count.
    private func ordinal(_ index: Int) -> some View {
        Text("\(index + 1)")
            .font(Typography.mono(11))
            .foregroundStyle(Tokens.Ink.primary)
            .frame(width: 20, height: 20)
            .background(Tokens.Ground.milk, in: Circle())
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)
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
