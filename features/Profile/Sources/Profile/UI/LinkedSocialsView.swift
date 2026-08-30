import DataKit
import DesignSystem
import SwiftUI

/// Linked socials. GLO-143, `docs/tech/02` §7.
public struct LinkedSocialsView: View {
    @State private var model: LinkedSocialsModel

    public init(store: LinkedSocialsStore) {
        _model = State(wrappedValue: LinkedSocialsModel(store: store))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                header
                if model.isLoading {
                    ProgressView()
                } else {
                    field
                    Text(model.stateLine)
                        .font(.system(size: Typography.Size.meta))
                        .foregroundStyle(Tokens.Ink.faint)
                    saveButton
                    note
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await model.load() }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Toast(message).padding(.bottom, Tokens.Space.s8)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("ELSEWHERE").eyebrow()
            Text("where else you are")
                .font(Typography.display(Typography.Size.h1))
                .foregroundStyle(Tokens.Ink.primary)
        }
    }

    private var field: some View {
        GlossedInput("@you on instagram, tiktok…", text: $model.typed)
    }

    private var saveButton: some View {
        Button(model.isSaving ? "saving…" : "save") {
            Task { await model.save() }
        }
        .buttonStyle(.glossed(.primary, block: true))
        .disabled(!model.canSave)
    }

    /// Says what the app will not do, because the safe behaviour is invisible
    /// and someone will otherwise expect a preview card.
    private var note: some View {
        Text("when it does show, it'll be plain text — we don't open or preview links.")
            .font(.system(size: Typography.Size.meta))
            .foregroundStyle(Tokens.Ink.soft)
    }
}
