import DataKit
import DesignSystem
import SwiftUI

/// The routine composer — the + drawer's "new routine" made real: name it,
/// slot it, sequence it from your shelf. No kit frame exists for this
/// screen (the drawer's own words are the spec: "am / pm · ordered steps"),
/// so it is built from the design system and workshopped in the PR — the
/// standing ruling for frameless surfaces.
public struct RoutineComposerView: View {
    @State private var model: RoutineComposerModel
    private let onClose: () -> Void
    private let onSaved: () -> Void

    public init(
        model: RoutineComposerModel,
        onClose: @escaping () -> Void,
        onSaved: @escaping () -> Void
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
                    Text("new\nroutine")
                        .font(Typography.display(32))
                        .tracking(-0.64)
                        .foregroundStyle(Tokens.Ink.primary)
                    GlossedInput(
                        "morning glass skin",
                        text: Binding(get: { model.title }, set: { model.title = $0 }),
                        label: "name"
                    )
                    Text("WHEN").eyebrow()
                    Segmented(
                        options: RoutineComposerModel.Slot.allCases.map(\.label),
                        selection: Binding(
                            get: { model.slot.label },
                            set: { picked in
                                model.slot = RoutineComposerModel.Slot.allCases
                                    .first { $0.label == picked } ?? .am
                            }
                        )
                    )
                    if !model.steps.isEmpty {
                        Text("THE ORDER").eyebrow()
                            .padding(.top, Tokens.Space.s1)
                        VStack(spacing: Tokens.Space.s2) {
                            ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                                stepRow(step, position: index + 1)
                            }
                        }
                    }
                    Text("FROM YOUR SHELF").eyebrow()
                        .padding(.top, Tokens.Space.s1)
                    shelfPicker
                    linkSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(.init(top: 18, leading: 22, bottom: 22, trailing: 22))
        .background(Tokens.Ground.milk)
        .task { model.loadShelf() }
    }

    /// A picked step: its position, its name, and the two arrows that are
    /// the whole reorder story — a routine is short, and neighbor swaps
    /// beat drag handles for six rows.
    private func stepRow(_ step: RoutineComposerModel.Step, position: Int) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            stepHeader(step, position: position)
            // The step's own words (0052): what you DO with it — "three
            // drops, pressed in" — under the product it applies to, so a
            // reorder carries the words with the step.
            TextField(
                "",
                text: noteBinding(for: step.id),
                prompt: Text("how you use it · optional").font(Typography.mono(11)),
                axis: .vertical
            )
            .font(Typography.mono(12))
            .foregroundStyle(Tokens.Ink.soft)
            .lineLimit(1 ... 3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Tokens.Space.s3)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
        )
    }

    /// The note, edited in place on the model's own array — found by id
    /// rather than index, so the binding survives a reorder mid-edit. The cap
    /// is the schema's 500, cut at the keyboard rather than as a 23514.
    private func noteBinding(for stepID: UUID) -> Binding<String> {
        Binding(
            get: { model.steps.first { $0.id == stepID }?.note ?? "" },
            set: { value in
                guard let index = model.steps.firstIndex(where: { $0.id == stepID }) else { return }
                model.steps[index].note = String(value.prefix(RoutineComposerModel.noteCap))
            }
        )
    }

    private func stepHeader(_ step: RoutineComposerModel.Step, position: Int) -> some View {
        HStack(spacing: Tokens.Space.s3) {
            Text("\(position)")
                .font(Typography.mono(11, bold: true))
                .foregroundStyle(Tokens.Ink.primary)
                .frame(width: 22, height: 22)
                .background(Tokens.Cherry.soft)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin))
            VStack(alignment: .leading, spacing: 1) {
                Text(step.name)
                    .font(Typography.display(14.5, weight: 700))
                    .foregroundStyle(Tokens.Ink.primary)
                    .lineLimit(1)
                Text(step.brand).meta()
            }
            Spacer(minLength: 0)
            Button {
                model.move(step, up: true)
            } label: {
                Image(systemName: "chevron.up")
                    .font(Typography.control(13, weight: .bold))
                    .foregroundStyle(position == 1 ? Tokens.Ink.faint : Tokens.Ink.primary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("move \(step.name) earlier")
            Button {
                model.move(step, up: false)
            } label: {
                Image(systemName: "chevron.down")
                    .font(Typography.control(13, weight: .bold))
                    .foregroundStyle(position == model.steps.count ? Tokens.Ink.faint : Tokens.Ink.primary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("move \(step.name) later")
        }
    }

    @ViewBuilder private var shelfPicker: some View {
        if model.isLoadingShelf {
            Text("fetching your shelf…").meta()
        } else if model.shelf.isEmpty {
            // Empty is explained, never blank: a routine sequences what
            // you own, and the door to owning things is named.
            Text("a routine is your shelf in order — log a product or two first, then come back")
                .meta()
        } else {
            VStack(spacing: Tokens.Space.s2) {
                ForEach(model.shelf) { row in
                    shelfRow(row)
                }
            }
        }
    }

    private func shelfRow(_ row: RoutineComposerModel.Step) -> some View {
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
            Button(model.isSaving ? "saving…" : "save routine") {
                model.save(onSaved: onSaved)
            }
            .buttonStyle(.glossed(block: true))
            .disabled(!model.canSave || model.isSaving)
            Text(model.canSave
                ? "\(model.steps.count) step\(model.steps.count == 1 ? "" : "s") · \(model.slot.label)"
                : "name it and pick at least one product")
                .meta()
                .frame(maxWidth: .infinity)
        }
        .padding(.top, Tokens.Space.s3)
    }

    /// Collections this routine goes with (0052) — chips, on/off, your own
    /// only, absent when there is nothing to offer.
    @ViewBuilder private var linkSection: some View {
        if !model.linkableCollections.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text("LINK A COLLECTION").eyebrow()
                    .padding(.top, Tokens.Space.s1)
                ForEach(model.linkableCollections) { pick in
                    Button {
                        model.toggleCollection(pick.id)
                    } label: {
                        HStack(spacing: Tokens.Space.s2) {
                            Text(pick.title)
                                .font(Typography.mono(12))
                                .foregroundStyle(Tokens.Ink.primary)
                            Spacer(minLength: 0)
                            if model.linkedCollectionIDs.contains(pick.id) {
                                Text("linked")
                                    .font(Typography.mono(11))
                                    .foregroundStyle(Tokens.Cherry.deep)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, Tokens.Space.s3)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                                .fill(model.linkedCollectionIDs.contains(pick.id)
                                    ? Tokens.Cherry.soft : Tokens.Ground.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.linkedCollectionIDs.contains(pick.id) ? .isSelected : [])
                }
            }
        }
    }
}
