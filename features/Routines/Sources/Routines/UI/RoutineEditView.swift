import DataKit
import DesignSystem
import SwiftUI

/// The routine, editable (GLO-272) — the uniform pattern: title, who sees
/// it, the steps (membership AND each step's note — Sean's per-step ask),
/// and the linked collections all stage behind the disabled-until-dirty
/// save; save confirms, delete confirms and warns, closing dirty asks.
///
/// The slot is shown, never edited: an am routine that becomes a pm routine
/// is a different routine.
public struct RoutineEditView: View {
    @State private var model: RoutineEditModel
    @State private var addingStep = false
    @State private var addingCollection = false
    @State private var stepOffer: [RoutineComposerModel.Step]?
    @State private var collectionOffer: [LinkablePick]?
    @State private var confirmingSave = false
    @State private var confirmingDelete = false
    @State private var confirmingDiscard = false
    private let slotLabel: String
    private let onDone: () -> Void
    private let onDeleted: () -> Void

    public init(
        model: RoutineEditModel,
        slotLabel: String,
        onDone: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.slotLabel = slotLabel
        self.onDone = onDone
        self.onDeleted = onDeleted
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                header
                scopeSection
                titleSection
                RoutineEditStepsSection(model: model, addingStep: $addingStep)
                RoutineEditLinksSection(model: model, addingCollection: $addingCollection)
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
            "delete this routine?", isPresented: $confirmingDelete, titleVisibility: .visible
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
            Text("the routine and its steps retract; your shelf keeps the products. unsaved edits are lost too.")
        }
        .confirmationDialog(
            "discard your edits?", isPresented: $confirmingDiscard, titleVisibility: .visible
        ) {
            Button("discard", role: .destructive) { onDone() }
            Button("keep editing", role: .cancel) {}
        }
        .sheet(isPresented: $addingStep) {
            stepSheet.presentationDetents([.medium])
        }
        .sheet(isPresented: $addingCollection) {
            collectionSheet.presentationDetents([.medium])
        }
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slotLabel).eyebrow()
                Text("edit routine")
                    .font(Typography.display(Typography.Size.h2))
                    .foregroundStyle(Tokens.Ink.primary)
            }
            Spacer(minLength: 0)
            Button("close") {
                if model.isDirty {
                    confirmingDiscard = true
                } else {
                    onDone()
                }
            }
            .buttonStyle(.glossed(.secondary, size: .sm))
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("WHO SEES IT").eyebrow()
            HStack(spacing: Tokens.Space.s2) {
                ForEach(PrivacyScope.allCases, id: \.self) { scope in
                    scopeChip(scope)
                }
            }
        }
    }

    private func scopeChip(_ scope: PrivacyScope) -> some View {
        let isOn = model.visibility == scope
        return Button(scope.label) {
            model.visibility = scope
        }
        .buttonStyle(.plain)
        .font(Typography.mono(12))
        .foregroundStyle(isOn ? Tokens.Ground.card : Tokens.Ink.primary)
        .padding(.vertical, 6)
        .padding(.horizontal, Tokens.Space.s3)
        .background(Capsule().fill(isOn ? Tokens.Ink.primary : Tokens.Ground.card))
        .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("TITLE").eyebrow()
            TextField("name this routine", text: $model.title)
                .font(Typography.display(Typography.Size.body))
                .foregroundStyle(Tokens.Ink.primary)
                .padding(Tokens.Space.s3)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md).fill(Tokens.Ground.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
                )
        }
    }

    private var stepSheet: some View {
        RoutineEditPickSheet(
            eyebrow: "ADD FROM YOUR SHELF",
            emptyLine: "everything on your shelf is already in this routine.",
            rows: stepOffer?.map { .init(id: $0.id, eyebrow: $0.brand, label: $0.name) },
            onPick: { id in
                if let step = stepOffer?.first(where: { $0.id == id }) {
                    model.steps.append(step)
                }
                addingStep = false
            }
        )
        .task { stepOffer = await model.addableSteps() }
    }

    private var collectionSheet: some View {
        RoutineEditPickSheet(
            eyebrow: "LINK A COLLECTION",
            emptyLine: "every collection you have is already linked.",
            rows: collectionOffer?.map { .init(id: $0.id, eyebrow: "collection", label: $0.title) },
            onPick: { id in
                if let pick = collectionOffer?.first(where: { $0.id == id }) {
                    model.collections.append(pick)
                }
                addingCollection = false
            }
        )
        .task { collectionOffer = await model.addableCollections() }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if case let .failed(message) = model.phase {
                Text(message).meta()
            }
            Button(model.phase == .saving ? "saving…" : "save changes") {
                confirmingSave = true
            }
            .buttonStyle(.glossed(.primary, block: true))
            .disabled(!model.isDirty || model.phase == .saving)
            Button("delete this routine") {
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
