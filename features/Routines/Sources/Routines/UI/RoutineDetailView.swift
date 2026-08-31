import DataKit
import DesignSystem
import SwiftUI

/// What the detail screen shows, loaded by the host — the routine's own
/// fields plus what it goes with, in one shape so a partial load cannot
/// render half a screen. `Own` because DataKit's `RoutineDetail` is the
/// BROWSE shape (a stranger's routine through the approved-text read) — the
/// `MyRoutine`/`BrowseRoutine` distinction, kept at the type name.
public struct OwnRoutineDetail: Sendable, Equatable {
    public let title: String
    public let slotLabel: String
    public let visibility: PrivacyScope
    public let steps: [RoutineComposerModel.Step]
    public let collections: [LinkablePick]

    public init(
        title: String, slotLabel: String, visibility: PrivacyScope,
        steps: [RoutineComposerModel.Step], collections: [LinkablePick]
    ) {
        self.title = title
        self.slotLabel = slotLabel
        self.visibility = visibility
        self.steps = steps
        self.collections = collections
    }
}

/// A routine, opened (GLO-272) — click the card, read the sequence, and the
/// edit button is the only door onto changing it (Sean's uniform pattern).
/// **No kit frame**: built from the design system under the standing
/// no-frames ruling, for Sean to workshop in the PR.
public struct RoutineDetailView: View {
    private let load: () async throws -> OwnRoutineDetail
    private let editStore: RoutineEditStore
    private let onClose: () -> Void
    private let onDeleted: () -> Void

    @State private var detail: OwnRoutineDetail?
    @State private var editing = false
    @State private var failed = false

    public init(
        load: @escaping () async throws -> OwnRoutineDetail,
        editStore: RoutineEditStore,
        onClose: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.load = load
        self.editStore = editStore
        self.onClose = onClose
        self.onDeleted = onDeleted
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                HStack(spacing: Tokens.Space.s3) {
                    Button("← back", action: onClose)
                        .buttonStyle(.plain)
                        .font(Typography.mono(12))
                        .foregroundStyle(Tokens.Semantic.accentText)
                        .underline()
                    Spacer(minLength: 0)
                    if detail != nil {
                        Button("edit") { editing = true }
                            .buttonStyle(.glossed(.secondary, size: .sm))
                    }
                }
                if let detail {
                    loaded(detail)
                } else if failed {
                    Text("that routine didn't load — try again.").meta()
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await reload() }
        .modifier(RoutineEditCover(isPresented: $editing) {
            if let detail {
                RoutineEditView(
                    model: RoutineEditModel(
                        baseline: RoutineEditModel.Baseline(
                            title: detail.title, visibility: detail.visibility,
                            steps: detail.steps, collections: detail.collections
                        ),
                        store: editStore
                    ),
                    slotLabel: detail.slotLabel,
                    onDone: {
                        editing = false
                        // Reload in place — the detail must show what was
                        // saved, not what it remembered.
                        self.detail = nil
                        Task { await reload() }
                    },
                    onDeleted: {
                        editing = false
                        onDeleted()
                    }
                )
            }
        })
    }

    private func loaded(_ detail: OwnRoutineDetail) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Text(detail.slotLabel).eyebrow()
                Text(detail.title)
                    .font(Typography.display(Typography.Size.h2))
                    .foregroundStyle(Tokens.Ink.primary)
                Text(
                    "\(detail.steps.count) \(detail.steps.count == 1 ? "step" : "steps")"
                        + " · \(detail.visibility.label)"
                )
                .meta()
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                ForEach(Array(detail.steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(index: index, step: step)
                }
            }
            goesWith(detail.collections)
        }
    }

    private func stepRow(index: Int, step: RoutineComposerModel.Step) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s3) {
            Text(String(index + 1))
                .font(Typography.mono(12, bold: true))
                .foregroundStyle(Tokens.Ink.soft)
                .frame(width: 18, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.brand).eyebrow()
                Text(step.name)
                    .font(Typography.display(Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.primary)
                if !step.note.isEmpty {
                    Text(step.note).meta()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.md).fill(Tokens.Ground.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
        )
    }

    @ViewBuilder private func goesWith(_ collections: [LinkablePick]) -> some View {
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text("GOES WITH").eyebrow()
                ForEach(collections) { pick in
                    HStack(spacing: Tokens.Space.s1) {
                        Text("collection")
                            .font(Typography.mono(10))
                            .foregroundStyle(Tokens.Ink.soft)
                        Text(pick.title)
                            .font(Typography.mono(12))
                            .foregroundStyle(Tokens.Ink.primary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, Tokens.Space.s3)
                    .background(Capsule().fill(Tokens.Ground.card))
                    .overlay(
                        Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
                    )
                }
            }
        }
    }

    private func reload() async {
        do {
            detail = try await load()
        } catch {
            failed = true
        }
    }
}

/// `fullScreenCover` is iOS-only; the macOS test build compiles this package
/// too — the `EditCover` trade, made here.
struct RoutineEditCover<Cover: View>: ViewModifier {
    let isPresented: Binding<Bool>
    @ViewBuilder let cover: () -> Cover

    func body(content: Content) -> some View {
        #if os(iOS)
            content.fullScreenCover(isPresented: isPresented, content: cover)
        #else
            content.sheet(isPresented: isPresented, content: cover)
        #endif
    }
}
