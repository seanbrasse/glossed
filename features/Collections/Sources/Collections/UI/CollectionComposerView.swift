import DataKit
import DesignSystem
import SwiftUI

/// The collection composer — the `+` drawer's "new collection" made real:
/// name it, tint it, fill it from your shelf.
///
/// No kit frame draws this screen. `G.Profile` draws the collections GRID
/// (four tinted cards, `N products` in mono) and the drawer's own words are
/// the rest of the spec — "group products your way" — so this is built from
/// the design system and workshopped in the PR, the standing ruling for
/// frameless surfaces. Its layout is `RoutineComposerView`'s on purpose: the
/// two doors sit next to each other in the same drawer and pick from the same
/// shelf, and two shapes for one gesture is a worse answer than one.
public struct CollectionComposerView: View {
    @State private var model: CollectionComposerModel
    private let onClose: () -> Void
    private let onSaved: (_ warning: String?) -> Void

    public init(
        model: CollectionComposerModel,
        onClose: @escaping () -> Void,
        onSaved: @escaping (_ warning: String?) -> Void
    ) {
        _model = State(initialValue: model)
        self.onClose = onClose
        self.onSaved = onSaved
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Button("← back", action: onClose)
                        .buttonStyle(.plain)
                        .font(Typography.mono(12))
                        .foregroundStyle(Tokens.Semantic.accentText)
                        .underline()
                    Text("new\ncollection")
                        .font(Typography.display(32))
                        .tracking(-0.64)
                        .foregroundStyle(Tokens.Ink.primary)
                    GlossedInput(
                        "holy grails only",
                        text: Binding(get: { model.title }, set: { model.title = $0 }),
                        label: "name"
                    )
                    Text("COVER").eyebrow()
                    tintPicker
                    Text("FROM YOUR SHELF").eyebrow()
                        .padding(.top, Tokens.Space.s1)
                    shelfPicker
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(.init(top: 18, leading: 22, bottom: 22, trailing: 22))
        .background(Tokens.Ground.milk)
        .task { model.loadShelf() }
    }

    /// The four covers the grid draws, plus none.
    ///
    /// **None is a real choice and it is the default**, because `cover_tint`
    /// is nullable and a card with no tint is what the column's absence means.
    /// Pre-selecting butter would put a colour on every collection anyone ever
    /// made and call it the user's pick.
    private var tintPicker: some View {
        HStack(spacing: Tokens.Space.s2) {
            tintSwatch(nil)
            ForEach(CollectionTint.allCases, id: \.self) { option in
                tintSwatch(option)
            }
            Spacer(minLength: 0)
        }
    }

    private func tintSwatch(_ option: CollectionTint?) -> some View {
        let chosen = model.tint == option
        return Button {
            model.tint = option
        } label: {
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .fill(option?.fill ?? Tokens.Ground.card)
                .frame(width: 52, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(
                            chosen ? Tokens.Ink.primary : Tokens.Ground.line,
                            lineWidth: chosen ? Tokens.Border.std : Tokens.Border.hair
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.pop(), value: chosen)
        .accessibilityLabel(option?.label ?? "no cover")
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    @ViewBuilder private var shelfPicker: some View {
        if model.isLoadingShelf {
            Text("fetching your shelf…").meta()
        } else if model.shelf.isEmpty {
            // Explained, never blank — and it does NOT block saving, because
            // an empty collection you named is a real thing to have made.
            Text("a collection groups things you own — log a product first, or name this one and fill it later")
                .meta()
        } else {
            VStack(spacing: Tokens.Space.s2) {
                ForEach(model.shelf) { row in
                    shelfRow(row)
                }
            }
        }
    }

    private func shelfRow(_ row: CollectionItem) -> some View {
        let picked = model.isPicked(row)
        return Button {
            model.toggle(row)
        } label: {
            HStack(spacing: Tokens.Space.s3) {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(Typography.control(18, weight: .semibold))
                    .foregroundStyle(picked ? Tokens.Cherry.base : Tokens.Ground.line)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name)
                        .font(Typography.display(14.5, weight: 700))
                        .foregroundStyle(Tokens.Ink.primary)
                        .lineLimit(1)
                    Text(row.brand).meta()
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, Tokens.Space.s3)
        }
        .buttonStyle(.plain)
        .background(picked ? Tokens.Support.mintSoft : Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(
                    picked ? Tokens.Ink.primary : Tokens.Ground.line,
                    lineWidth: picked ? Tokens.Border.thin : Tokens.Border.hair
                )
        )
        .animation(Tokens.Motion.pop(), value: picked)
        .accessibilityAddTraits(picked ? [.isSelected] : [])
    }

    private var footer: some View {
        VStack(spacing: Tokens.Space.s2) {
            if let error = model.saveError {
                Text(error.userMessage).meta()
            }
            Button(model.isSaving ? "saving…" : "save collection") {
                model.save(onSaved: onSaved)
            }
            .buttonStyle(.glossed(block: true))
            .disabled(!model.canSave || model.isSaving)
            Text(model.summary)
                .meta()
                .frame(maxWidth: .infinity)
        }
        .padding(.top, Tokens.Space.s3)
    }
}
