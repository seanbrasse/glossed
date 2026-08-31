import DesignSystem
import SwiftUI

// The post's GOES WITH section (0050), split from `LookPostView` for the
// 300-line ceiling — and, when the host hands over an editor, the owner's
// way to change their mind: the composer writes links once at post time, so
// without this an unlinked routine stayed unlinked forever.

/// The owner's link controls, as closures the app fills. Nil on the view
/// renders the chips read-only — a stranger's post never edits.
public struct LookLinkEditor: Sendable {
    public var linkables: @Sendable () async throws -> LookLinkables
    public var link: @Sendable (_ routineIDs: [UUID], _ collectionIDs: [UUID]) async throws -> Void
    public var unlinkRoutine: @Sendable (UUID) async throws -> Void
    public var unlinkCollection: @Sendable (UUID) async throws -> Void

    public init(
        linkables: @escaping @Sendable () async throws -> LookLinkables,
        link: @escaping @Sendable ([UUID], [UUID]) async throws -> Void,
        unlinkRoutine: @escaping @Sendable (UUID) async throws -> Void,
        unlinkCollection: @escaping @Sendable (UUID) async throws -> Void
    ) {
        self.linkables = linkables
        self.link = link
        self.unlinkRoutine = unlinkRoutine
        self.unlinkCollection = unlinkCollection
    }
}

/// GOES WITH — chips under the caption. Attribution, never a claim
/// (GLO-196): no counts, no evidence chrome, and a link the policies hid
/// simply is not here.
///
/// The section owns its truth after load: an unlink removes the chip in
/// place the moment the write returns, and a failed write puts nothing back
/// silently — it names itself (the `saveRename` rules, both of them).
struct LookLinksSection: View {
    @State private var routines: [LinkablePick]
    @State private var collections: [LinkablePick]
    @State private var isEditing = false
    @State private var adding = false
    @State private var failure: String?
    private let editor: LookLinkEditor?

    init(routines: [LinkablePick], collections: [LinkablePick], editor: LookLinkEditor?) {
        _routines = State(initialValue: routines)
        _collections = State(initialValue: collections)
        self.editor = editor
    }

    var body: some View {
        // Empty AND read-only is nothing to draw; empty with an editor is
        // the door onto linking after the fact.
        if !routines.isEmpty || !collections.isEmpty || editor != nil {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                HStack(spacing: Tokens.Space.s2) {
                    Text("GOES WITH").eyebrow()
                    if editor != nil {
                        Button(isEditing ? "done" : "edit") {
                            withAnimation(Tokens.Motion.pop(Tokens.Motion.fast)) {
                                isEditing.toggle()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(Typography.mono(11))
                        .foregroundStyle(Tokens.Semantic.accentText)
                        .underline()
                    }
                    Spacer(minLength: 0)
                }
                FlowLayoutCompat(spacing: Tokens.Space.s2) {
                    ForEach(routines) { pick in
                        chip(pick.title, kind: "routine") { unlink(routine: pick) }
                    }
                    ForEach(collections) { pick in
                        chip(pick.title, kind: "collection") { unlink(collection: pick) }
                    }
                    if isEditing {
                        Button("+ link") { adding = true }
                            .buttonStyle(.plain)
                            .font(Typography.mono(12))
                            .foregroundStyle(Tokens.Cherry.deep)
                            .padding(.vertical, 6)
                            .padding(.horizontal, Tokens.Space.s3)
                            .overlay(
                                Capsule().strokeBorder(
                                    Tokens.Cherry.deep, style: StrokeStyle(lineWidth: Tokens.Border.hair, dash: [4, 3])
                                )
                            )
                    }
                }
                if let failure {
                    Text(failure).meta()
                }
            }
            .sheet(isPresented: $adding) {
                if let editor {
                    LookLinkPickerSheet(
                        editor: editor,
                        alreadyRoutines: Set(routines.map(\.id)),
                        alreadyCollections: Set(collections.map(\.id)),
                        onLinked: { newRoutines, newCollections in
                            routines.append(contentsOf: newRoutines)
                            collections.append(contentsOf: newCollections)
                            adding = false
                        }
                    )
                    .presentationDetents([.medium])
                }
            }
        }
    }

    /// The chip, wearing an × only in edit mode — the whole chip is the
    /// remove target then, because a 10pt glyph is not a tap target.
    private func chip(_ title: String, kind: String, remove: @escaping () -> Void) -> some View {
        Button {
            if isEditing {
                remove()
            }
        } label: {
            HStack(spacing: Tokens.Space.s1) {
                Text(kind)
                    .font(Typography.mono(10))
                    .foregroundStyle(Tokens.Ink.soft)
                Text(title)
                    .font(Typography.mono(12))
                    .foregroundStyle(Tokens.Ink.primary)
                if isEditing {
                    Text("×")
                        .font(Typography.mono(12, bold: true))
                        .foregroundStyle(Tokens.Cherry.deep)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, Tokens.Space.s3)
            .background(Capsule().fill(Tokens.Ground.card))
            .overlay(
                Capsule().strokeBorder(
                    isEditing ? Tokens.Cherry.deep : Tokens.Ink.primary,
                    lineWidth: Tokens.Border.hair
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEditing)
        .accessibilityLabel(isEditing ? "unlink \(title)" : title)
    }

    /// Chip off the moment the write returns — in place, no reload, no
    /// spinner over a list that is already correct. A failure restores it
    /// and says so: silently losing a link the user still sees is GLO-278's
    /// shape from the other side.
    private func unlink(routine pick: LinkablePick) {
        guard let editor else { return }
        routines.removeAll { $0.id == pick.id }
        Task {
            do {
                try await editor.unlinkRoutine(pick.id)
            } catch {
                routines.append(pick)
                failure = "couldn't unlink \(pick.title) — try again."
            }
        }
    }

    private func unlink(collection pick: LinkablePick) {
        guard let editor else { return }
        collections.removeAll { $0.id == pick.id }
        Task {
            do {
                try await editor.unlinkCollection(pick.id)
            } catch {
                collections.append(pick)
                failure = "couldn't unlink \(pick.title) — try again."
            }
        }
    }
}

/// The add half: what you could link and have not. Same chips as the
/// composer's section, filtered to what is missing, written on tap.
private struct LookLinkPickerSheet: View {
    let editor: LookLinkEditor
    let alreadyRoutines: Set<UUID>
    let alreadyCollections: Set<UUID>
    let onLinked: ([LinkablePick], [LinkablePick]) -> Void

    @State private var offer: LookLinkables?
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text("LINK TO THIS LOOK").eyebrow()
                if let offer {
                    let routines = offer.routines.filter { !alreadyRoutines.contains($0.id) }
                    let collections = offer.collections.filter { !alreadyCollections.contains($0.id) }
                    if routines.isEmpty, collections.isEmpty {
                        Text("everything you have is already linked.").meta()
                    }
                    ForEach(routines) { pick in
                        row(pick, kind: "routine") { link(routines: [pick], collections: []) }
                    }
                    ForEach(collections) { pick in
                        row(pick, kind: "collection") { link(routines: [], collections: [pick]) }
                    }
                    if let failure {
                        Text(failure).meta()
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(Tokens.Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Ground.milk)
        .task { offer = try? await editor.linkables() }
    }

    private func row(_ pick: LinkablePick, kind: String, add: @escaping () -> Void) -> some View {
        Button(action: add) {
            HStack(spacing: Tokens.Space.s2) {
                Text(kind).font(Typography.mono(10)).foregroundStyle(Tokens.Ink.soft)
                Text(pick.title)
                    .font(Typography.mono(12))
                    .foregroundStyle(Tokens.Ink.primary)
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

    private func link(routines: [LinkablePick], collections: [LinkablePick]) {
        Task {
            do {
                try await editor.link(routines.map(\.id), collections.map(\.id))
                onLinked(routines, collections)
            } catch {
                failure = "that link didn't save — try again."
            }
        }
    }
}
