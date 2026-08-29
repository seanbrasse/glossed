import DataKit
import DesignSystem
import Shelf
import SwiftUI

/// The post-log fit ask (GLO-16): shown once, right after the ladder closes,
/// and only for a log in an anchor category — an anchor's shade is evidence
/// (`Category.isAnchor`), so the moment a product lands is the one moment the
/// app may ask how it sat. `FitControl`'s own doc is the spec: "asked on every
/// log of an anchor-category product, not buried in a rating flow."
///
/// Lives in the app layer on purpose (the option-1 decision on GLO-16): the
/// ladder reports the row, the `Fit`↔`FitAnswer` translation stays in Shelf's
/// `ShelfFitStore`, and features never import features — the shell is the one
/// place both halves are visible. The kit has no frame for this card; it is
/// built from primitives to the spirit of `G.OnbBuild`'s "found it — did it
/// fit?" moment, and Sean workshops it in review.
struct FitPromptCard: View {
    let store: ShelfFitStore
    let itemID: UUID
    let onDone: () -> Void

    @State private var selection: Set<FitAnswer> = []
    @State private var isSaving = false
    @State private var failure: GlossedError?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Text("ON YOUR SHELF").eyebrow()
                Text("did it fit?").font(Typography.display(24))
                    .foregroundStyle(Tokens.Ink.primary)
            }
            FitControl(selection: $selection)
            if let failure {
                Text(failure.userMessage).meta()
            }
            HStack(spacing: Tokens.Space.s3) {
                // Skipping is a real answer — most people log in five seconds.
                // No write happens on skip, so nothing is claimed.
                Button("skip") { onDone() }
                    .buttonStyle(.glossed(.secondary))
                Button(isSaving ? "saving…" : "save") { save() }
                    .buttonStyle(.glossed())
                    .disabled(selection.isEmpty || isSaving)
            }
        }
        .padding(Tokens.Space.s5)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        )
        .padding(Tokens.Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Ink.primary.opacity(0.4))
        .ignoresSafeArea()
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        failure = nil
        Task {
            defer { isSaving = false }
            do {
                try await store.save(itemID, selection)
                onDone()
            } catch {
                // The card stays up with the picked answers — a failed save
                // that quietly closed would look exactly like a saved one.
                failure = GlossedError.from(error)
            }
        }
    }
}
