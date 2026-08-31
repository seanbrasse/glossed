import DataKit
import DesignSystem
import SwiftUI

/// The look, editable (GLO-272) — Sean's uniform pattern: click into the
/// thing, hit edit, and every change stages behind a save button that starts
/// disabled and arms on the first change. Save confirms; delete confirms and
/// warns of lost progress.
///
/// **No kit frame** (the post view's own note): built from the design system
/// under the standing no-frames ruling, for Sean to workshop in the PR.
///
/// What is editable: caption, tagged products, linked routines/collections,
/// who sees it, and whether it is posted. What is not: the photos — the
/// ruling makes images immutable after the composer, so the strip here
/// selects a photo to re-tag and nothing else.
public struct LookEditView: View {
    @State private var model: LookEditModel
    @State private var taggingPhotoID: UUID?
    @State private var confirmingSave = false
    @State private var confirmingDelete = false
    @State private var confirmingDiscard = false
    private let media: [LookMedia]
    private let search: LookTagSearch
    private let onDone: () -> Void
    private let onDeleted: () -> Void

    public init(
        model: LookEditModel,
        media: [LookMedia],
        search: LookTagSearch,
        onDone: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.media = media.sorted { $0.position < $1.position }
        self.search = search
        self.onDone = onDone
        self.onDeleted = onDeleted
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                header
                LookEditReachSection(model: model)
                caption
                tagging
                LookEditLinksSection(model: model)
                footer
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .confirmationDialog("save these changes?", isPresented: $confirmingSave, titleVisibility: .visible) {
            Button("save") {
                Task {
                    if await model.save() {
                        onDone()
                    }
                }
            }
            Button("keep editing", role: .cancel) {}
        }
        .confirmationDialog(
            "delete this look?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("delete it", role: .destructive) {
                Task {
                    if await model.delete() {
                        onDeleted()
                    }
                }
            }
            Button("keep it", role: .cancel) {}
        } message: {
            Text("its photos and tags go with it, and there's no undo. unsaved edits are lost too.")
        }
        .confirmationDialog(
            "discard your edits?", isPresented: $confirmingDiscard, titleVisibility: .visible
        ) {
            Button("discard", role: .destructive) { onDone() }
            Button("keep editing", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.s3) {
            Text("edit look")
                .font(Typography.display(Typography.Size.h2))
                .foregroundStyle(Tokens.Ink.primary)
            Spacer(minLength: 0)
            Button("close") {
                // Dirty edits deserve a question, not a silent drop — the
                // same courtesy the delete dialog's warning extends.
                if model.isDirty {
                    confirmingDiscard = true
                } else {
                    onDone()
                }
            }
            .buttonStyle(GlossedButtonStyle(.secondary, size: .sm))
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("CAPTION").eyebrow()
            TextField("say something about it", text: $model.caption, axis: .vertical)
                .font(Typography.display(Typography.Size.body))
                .foregroundStyle(Tokens.Ink.primary)
                .lineLimit(3 ... 5)
                .padding(Tokens.Space.s3)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md).fill(Tokens.Ground.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
                )
        }
    }

    // MARK: - re-tagging (the composer's canvas, over remote photos)

    private var tagging: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("TAG WHAT YOU'RE WEARING").eyebrow()
            if media.count > 1 {
                strip
            }
            if let photo = currentPhoto {
                LookTagCanvas(board: $model.board, photoID: photo.id, search: search) {
                    photoImage(photo)
                }
                .id(photo.id)
            }
        }
    }

    private var currentPhoto: LookMedia? {
        taggingPhotoID.flatMap { id in media.first { $0.id == id } } ?? media.first
    }

    /// The composer's strip, read-only about content: photos cannot be added,
    /// removed, or reordered here — a tile is only the way to pick which
    /// photo the canvas shows.
    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s2) {
                ForEach(media) { item in
                    Button {
                        taggingPhotoID = item.id
                    } label: {
                        photoImage(item)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                                    .strokeBorder(
                                        currentPhoto?.id == item.id
                                            ? Tokens.Cherry.deep : Tokens.Ink.primary,
                                        lineWidth: currentPhoto?.id == item.id
                                            ? Tokens.Border.std : Tokens.Border.hair
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Squared by the container, never by the image (GLO-252's remedy — the
    /// composer's own comment, and its bug).
    private func photoImage(_ item: LookMedia) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                switch item.kind {
                case let .photo(source):
                    switch source {
                    case let .remote(url):
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Tokens.Support.lilacSoft)
                        }
                    case .data, .unavailable:
                        Rectangle().fill(Tokens.Support.lilacSoft)
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }

    // MARK: - save and delete

    private var footer: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if case let .failed(message) = model.phase {
                Text(message).meta()
            }
            Button(model.phase == .saving ? "saving…" : "save changes") {
                confirmingSave = true
            }
            .buttonStyle(GlossedButtonStyle(.primary, block: true))
            // Disabled until the first change — Sean's spec, verbatim.
            .disabled(!model.isDirty || model.phase == .saving)
            Button("delete this look") {
                confirmingDelete = true
            }
            .buttonStyle(.plain)
            .font(Typography.mono(12))
            .foregroundStyle(Tokens.Cherry.deep)
            .underline()
            .frame(maxWidth: .infinity)
            .disabled(model.phase == .deleting)
        }
    }
}
