import DataKit
import DesignSystem
import SwiftUI

// The edit screen's reach and links halves, split from `LookEditView.swift`
// for the 300-line ceiling — the `ComposerTagSection` split, again.

/// WHO SEES IT + whether it is posted — Sean's archive ruling as two
/// controls: scope chips (private / friends / public) and the unpost row.
/// Both STAGE; nothing writes until the save button.
struct LookEditReachSection: View {
    @Bindable var model: LookEditModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text("WHO SEES IT").eyebrow()
                HStack(spacing: Tokens.Space.s2) {
                    ForEach(PrivacyScope.allCases, id: \.self) { scope in
                        chip(scope)
                    }
                }
                if model.visibility == .onlyYou, model.isPosted {
                    // The archive state, named: still posted, reaching nobody.
                    Text("archived — posted, but only you can see it.").meta()
                }
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text("POSTED").eyebrow()
                HStack(spacing: Tokens.Space.s2) {
                    Text(model.isPosted ? "on your profile" : "a draft — not posted")
                        .font(Typography.display(Typography.Size.small))
                        .foregroundStyle(Tokens.Ink.primary)
                    Spacer(minLength: 0)
                    Button(model.isPosted ? "unpost" : "post") {
                        model.isPosted.toggle()
                    }
                    .buttonStyle(GlossedButtonStyle(.secondary, size: .sm))
                }
            }
        }
    }

    private func chip(_ scope: PrivacyScope) -> some View {
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
}

/// GOES WITH, staged: chips with an × that only edits the DRAFT — the diffs
/// reach the tables when the save button writes them, unlike the post view's
/// `LookLinksSection`, which writes immediately and predates the uniform
/// edit ruling.
struct LookEditLinksSection: View {
    @Bindable var model: LookEditModel
    @State private var adding = false
    @State private var offer: LookLinkables?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("GOES WITH").eyebrow()
            FlowLayoutCompat(spacing: Tokens.Space.s2) {
                ForEach(model.routines) { pick in
                    chip(pick.title, kind: "routine") {
                        model.routines.removeAll { $0.id == pick.id }
                    }
                }
                ForEach(model.collections) { pick in
                    chip(pick.title, kind: "collection") {
                        model.collections.removeAll { $0.id == pick.id }
                    }
                }
                Button("+ link") { adding = true }
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
        .sheet(isPresented: $adding) {
            picker.presentationDetents([.medium])
        }
    }

    private func chip(_ title: String, kind: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: Tokens.Space.s1) {
                Text(kind).font(Typography.mono(10)).foregroundStyle(Tokens.Ink.soft)
                Text(title).font(Typography.mono(12)).foregroundStyle(Tokens.Ink.primary)
                Text("×").font(Typography.mono(12, bold: true)).foregroundStyle(Tokens.Cherry.deep)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, Tokens.Space.s3)
            .background(Capsule().fill(Tokens.Ground.card))
            .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("unlink \(title)")
    }

    /// What you could link and have not — the composer's offer, filtered to
    /// what is missing. Selection only APPENDS to the draft; the diff
    /// happens at save.
    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text("LINK TO THIS LOOK").eyebrow()
                if let offer {
                    let linkedRoutines = Set(model.routines.map(\.id))
                    let linkedCollections = Set(model.collections.map(\.id))
                    let routines = offer.routines.filter { !linkedRoutines.contains($0.id) }
                    let collections = offer.collections.filter { !linkedCollections.contains($0.id) }
                    if routines.isEmpty, collections.isEmpty {
                        Text("everything you have is already linked.").meta()
                    }
                    ForEach(routines) { pick in
                        row(pick, kind: "routine") { model.routines.append(pick) }
                    }
                    ForEach(collections) { pick in
                        row(pick, kind: "collection") { model.collections.append(pick) }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(Tokens.Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Ground.milk)
        .task { offer = await model.loadLinkables() }
    }

    private func row(_ pick: LinkablePick, kind: String, add: @escaping () -> Void) -> some View {
        Button {
            add()
            adding = false
        } label: {
            HStack(spacing: Tokens.Space.s2) {
                Text(kind).font(Typography.mono(10)).foregroundStyle(Tokens.Ink.soft)
                Text(pick.title).font(Typography.mono(12)).foregroundStyle(Tokens.Ink.primary)
                Spacer(minLength: 0)
                Text("link").font(Typography.mono(11)).foregroundStyle(Tokens.Cherry.deep)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, Tokens.Space.s3)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md).fill(Tokens.Ground.card))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
