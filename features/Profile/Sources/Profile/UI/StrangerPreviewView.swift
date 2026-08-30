import DataKit
import DesignSystem
import SwiftUI

/// "What a stranger sees." GLO-190.
public struct StrangerPreviewView: View {
    @State private var model: StrangerPreviewModel

    public init(store: StrangerPreviewStore) {
        _model = State(wrappedValue: StrangerPreviewModel(store: store))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                header
                if model.isLoading {
                    ProgressView()
                } else if model.needsHandle {
                    Text("claim a handle first — there's nothing for anyone to find yet.")
                        .font(.system(size: Typography.Size.body))
                        .foregroundStyle(Tokens.Ink.soft)
                } else if let preview = model.preview {
                    card(preview)
                    surfaces(preview)
                    if let line = model.friendsLine {
                        Text(line)
                            .font(.system(size: Typography.Size.meta))
                            .foregroundStyle(Tokens.Ink.soft)
                    }
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("WHAT A STRANGER SEES").eyebrow()
            Text("your profile, to someone who isn't signed in")
                .font(Typography.display(Typography.Size.h2))
                .foregroundStyle(Tokens.Ink.primary)
        }
    }

    private func card(_ preview: StrangerPreview) -> some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text("@\(preview.handle)")
                    .font(Typography.display(Typography.Size.h3))
                    .foregroundStyle(Tokens.Ink.primary)
                if let name = preview.displayName {
                    Text(name)
                        .font(.system(size: Typography.Size.small))
                        .foregroundStyle(Tokens.Ink.soft)
                }
                if let bio = preview.bio {
                    Text(bio)
                        .font(.system(size: Typography.Size.small))
                        .foregroundStyle(Tokens.Ink.primary)
                }
                let badges = [preview.skinType, preview.anchor, preview.hairPattern].compactMap(\.self)
                if badges.isEmpty {
                    Text("no badges — you haven't published any.")
                        .font(.system(size: Typography.Size.meta))
                        .foregroundStyle(Tokens.Ink.faint)
                } else {
                    HStack(spacing: Tokens.Space.s2) {
                        ForEach(badges, id: \.self) { Badge($0, tone: .lilac) }
                    }
                }
                if preview.nothingIsPublic {
                    Text("your handle is all they get. everything else is private.")
                        .font(.system(size: Typography.Size.meta))
                        .foregroundStyle(Tokens.Ink.soft)
                }
            }
        }
    }

    private func surfaces(_ preview: StrangerPreview) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            ForEach(preview.visibleSurfaces, id: \.label) { surface in
                HStack {
                    Text(surface.label)
                        .font(.system(size: Typography.Size.body))
                        .foregroundStyle(surface.visible ? Tokens.Ink.primary : Tokens.Ink.faint)
                    Spacer()
                    Text(surface.visible ? "they can open this" : "hidden")
                        .font(.system(size: Typography.Size.meta))
                        .foregroundStyle(surface.visible ? Tokens.Support.mint : Tokens.Ink.faint)
                }
            }
        }
    }
}
