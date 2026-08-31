import DataKit
import DesignSystem
import SwiftUI

/// The collection, editable (GLO-272) — the look edit screen's pattern:
/// title, who sees it, and the items all stage; the save button starts
/// disabled and arms on the first change; save confirms; delete confirms and
/// warns of lost progress; closing dirty asks first.
public struct CollectionEditView: View {
    @State private var model: CollectionEditModel
    @State private var adding = false
    @State private var addables: [CollectionItem]?
    @State private var confirmingSave = false
    @State private var confirmingDelete = false
    @State private var confirmingDiscard = false
    private let onDone: () -> Void
    private let onDeleted: () -> Void

    public init(
        model: CollectionEditModel,
        onDone: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onDone = onDone
        self.onDeleted = onDeleted
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                header
                scopeSection
                titleSection
                itemsSection
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
            "delete this collection?", isPresented: $confirmingDelete, titleVisibility: .visible
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
            Text("the grouping goes; the products stay on your shelf. unsaved edits are lost too.")
        }
        .confirmationDialog(
            "discard your edits?", isPresented: $confirmingDiscard, titleVisibility: .visible
        ) {
            Button("discard", role: .destructive) { onDone() }
            Button("keep editing", role: .cancel) {}
        }
        .sheet(isPresented: $adding) {
            addSheet.presentationDetents([.medium])
        }
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.s3) {
            Text("edit collection")
                .font(Typography.display(Typography.Size.h2))
                .foregroundStyle(Tokens.Ink.primary)
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
            TextField("name this collection", text: $model.title)
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

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("IN THIS COLLECTION").eyebrow()
            if model.items.isEmpty {
                Text("nothing yet — add from your shelf.").meta()
            }
            ForEach(model.items) { item in
                HStack(spacing: Tokens.Space.s2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.brand).eyebrow()
                        Text(item.name)
                            .font(Typography.display(Typography.Size.small))
                            .foregroundStyle(Tokens.Ink.primary)
                    }
                    Spacer(minLength: 0)
                    Button("×") {
                        model.items.removeAll { $0.id == item.id }
                    }
                    .buttonStyle(.plain)
                    .font(Typography.mono(14, bold: true))
                    .foregroundStyle(Tokens.Cherry.deep)
                    .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                    .accessibilityLabel("remove \(item.name)")
                }
                .padding(.horizontal, Tokens.Space.s3)
                .padding(.vertical, Tokens.Space.s2)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md).fill(Tokens.Ground.card))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
                )
            }
            Button("+ add from your shelf") { adding = true }
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

    private var addSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text("ADD FROM YOUR SHELF").eyebrow()
                if let addables {
                    if addables.isEmpty {
                        Text("everything on your shelf is already in here.").meta()
                    }
                    ForEach(addables) { item in
                        Button {
                            model.items.append(item)
                            adding = false
                        } label: {
                            HStack(spacing: Tokens.Space.s2) {
                                Text(item.brand).font(Typography.mono(10)).foregroundStyle(Tokens.Ink.soft)
                                Text(item.name)
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
        .task { addables = await model.addables() }
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
            Button("delete this collection") {
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
