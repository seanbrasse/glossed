import DataKit
import DesignSystem
import SwiftUI

// The edit screen's steps and links halves, split from `RoutineEditView.swift`
// for the 300-line ceiling — the `LookEditSections` split, again.

/// STEPS, staged whole: membership, order, and each step's note (Sean's
/// per-step ask — the note field IS the row).
struct RoutineEditStepsSection: View {
    @Bindable var model: RoutineEditModel
    @Binding var addingStep: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("STEPS").eyebrow()
            if model.steps.isEmpty {
                Text("no steps — add from your shelf.").meta()
            }
            ForEach($model.steps) { $step in
                stepRow($step)
            }
            DashedAddChip(label: "+ add a step") { addingStep = true }
        }
    }

    private func stepRow(_ step: Binding<RoutineComposerModel.Step>) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            HStack(spacing: Tokens.Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.wrappedValue.brand).eyebrow()
                    Text(step.wrappedValue.name)
                        .font(Typography.display(Typography.Size.small))
                        .foregroundStyle(Tokens.Ink.primary)
                }
                Spacer(minLength: 0)
                Button("×") {
                    model.steps.removeAll { $0.id == step.wrappedValue.id }
                }
                .buttonStyle(.plain)
                .font(Typography.mono(14, bold: true))
                .foregroundStyle(Tokens.Cherry.deep)
                .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                .accessibilityLabel("remove \(step.wrappedValue.name)")
            }
            TextField("what you do in this step", text: step.note, axis: .vertical)
                .font(Typography.mono(12))
                .foregroundStyle(Tokens.Ink.primary)
                .lineLimit(1 ... 3)
                .onChange(of: step.wrappedValue.note) { _, note in
                    // The schema bounds a note at 500; refuse at the
                    // keyboard rather than as a 23514 — the composer's rule.
                    if note.count > RoutineComposerModel.noteCap {
                        step.wrappedValue.note = String(note.prefix(RoutineComposerModel.noteCap))
                    }
                }
        }
        .padding(Tokens.Space.s3)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md).fill(Tokens.Ground.card))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
        )
    }
}

/// GOES WITH, staged — chips with an × that only edits the draft; the diffs
/// reach `routine_collections` when the save button writes them.
struct RoutineEditLinksSection: View {
    @Bindable var model: RoutineEditModel
    @Binding var addingCollection: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("GOES WITH").eyebrow()
            ForEach(model.collections) { pick in
                HStack(spacing: Tokens.Space.s1) {
                    Text("collection").font(Typography.mono(10)).foregroundStyle(Tokens.Ink.soft)
                    Text(pick.title).font(Typography.mono(12)).foregroundStyle(Tokens.Ink.primary)
                    Button("×") {
                        model.collections.removeAll { $0.id == pick.id }
                    }
                    .buttonStyle(.plain)
                    .font(Typography.mono(12, bold: true))
                    .foregroundStyle(Tokens.Cherry.deep)
                    .accessibilityLabel("unlink \(pick.title)")
                }
                .padding(.vertical, 6)
                .padding(.horizontal, Tokens.Space.s3)
                .background(Capsule().fill(Tokens.Ground.card))
                .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair))
            }
            DashedAddChip(label: "+ link a collection") { addingCollection = true }
        }
    }
}

/// The dashed cherry "+ …" chip both sections open their sheets with.
struct DashedAddChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(Typography.mono(12))
            .foregroundStyle(Tokens.Cherry.deep)
            .padding(.vertical, 6)
            .padding(.horizontal, Tokens.Space.s3)
            .overlay(
                Capsule().strokeBorder(
                    Tokens.Cherry.deep,
                    style: StrokeStyle(lineWidth: Tokens.Border.hair, dash: [4, 3])
                )
            )
    }
}

/// One picker sheet for both offers — the rows differ, the chrome does not.
struct RoutineEditPickSheet: View {
    struct Row: Identifiable {
        let id: UUID
        let eyebrow: String
        let label: String
    }

    let eyebrow: String
    let emptyLine: String
    let rows: [Row]?
    let onPick: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text(eyebrow).eyebrow()
                if let rows {
                    if rows.isEmpty {
                        Text(emptyLine).meta()
                    }
                    ForEach(rows) { row in
                        Button {
                            onPick(row.id)
                        } label: {
                            HStack(spacing: Tokens.Space.s2) {
                                Text(row.eyebrow)
                                    .font(Typography.mono(10))
                                    .foregroundStyle(Tokens.Ink.soft)
                                Text(row.label)
                                    .font(Typography.mono(12))
                                    .foregroundStyle(Tokens.Ink.primary)
                                Spacer(minLength: 0)
                                Text("add").font(Typography.mono(11)).foregroundStyle(Tokens.Cherry.deep)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, Tokens.Space.s3)
                            .background(
                                RoundedRectangle(cornerRadius: Tokens.Radius.md).fill(Tokens.Ground.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(Tokens.Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Ground.milk)
    }
}
