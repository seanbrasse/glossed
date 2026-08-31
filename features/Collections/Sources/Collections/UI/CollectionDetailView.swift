import DataKit
import DesignSystem
import SwiftUI

/// A collection, opened (GLO-272) — click the card, see the grouping, and
/// the edit button is the only door onto changing it (Sean's uniform
/// pattern). **No kit frame**: built from the design system under the
/// standing no-frames ruling, for Sean to workshop in the PR.
public struct CollectionDetailView: View {
    private let collectionID: UUID
    private let store: CollectionsStore
    private let onClose: () -> Void
    /// Fires after the edit screen deleted the collection — the host closes
    /// this screen too, since there is nothing left to detail.
    private let onDeleted: () -> Void

    @State private var summary: CollectionSummary?
    @State private var items: [CollectionItem]?
    @State private var editing = false
    @State private var failed = false

    public init(
        collectionID: UUID,
        store: CollectionsStore,
        onClose: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.collectionID = collectionID
        self.store = store
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
                    if summary != nil, items != nil {
                        Button("edit") { editing = true }
                            .buttonStyle(.glossed(.secondary, size: .sm))
                    }
                }
                if let summary, let items {
                    loaded(summary, items)
                } else if failed {
                    Text("that collection didn't load — try again.").meta()
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await load() }
        .modifier(EditCover(isPresented: $editing) {
            if let summary, let items {
                CollectionEditView(
                    model: CollectionEditModel(
                        collectionID: collectionID,
                        baseline: CollectionEditModel.Baseline(
                            title: summary.title, visibility: summary.visibility, items: items
                        ),
                        store: store
                    ),
                    onDone: {
                        editing = false
                        // Reload in place — the detail must show what was
                        // saved, not what it remembered.
                        self.summary = nil
                        self.items = nil
                        Task { await load() }
                    },
                    onDeleted: {
                        editing = false
                        onDeleted()
                    }
                )
            }
        })
    }

    private func loaded(_ summary: CollectionSummary, _ items: [CollectionItem]) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Text(summary.title)
                    .font(Typography.display(Typography.Size.h2))
                    .foregroundStyle(Tokens.Ink.primary)
                Text(
                    "\(items.count) \(items.count == 1 ? "product" : "products")"
                        + " · \(summary.visibility.label)"
                )
                .meta()
            }
            if items.isEmpty {
                Text("nothing in here yet — edit to add from your shelf.").meta()
            } else {
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.brand).eyebrow()
                            Text(item.name)
                                .font(Typography.display(Typography.Size.small))
                                .foregroundStyle(Tokens.Ink.primary)
                        }
                        .padding(Tokens.Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Tokens.Radius.md).fill(Tokens.Ground.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
                        )
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            async let mine = store.mine()
            async let held = store.items(collectionID)
            let all = try await mine
            guard let found = all.first(where: { $0.id == collectionID }) else {
                failed = true
                return
            }
            summary = found
            items = try await held
        } catch {
            failed = true
        }
    }
}

/// `fullScreenCover` is iOS-only; the macOS test build compiles this package
/// too, so the presentation goes behind a platform check — the `PagedTabStyle`
/// trade, made here for a cover.
private struct EditCover<Cover: View>: ViewModifier {
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
