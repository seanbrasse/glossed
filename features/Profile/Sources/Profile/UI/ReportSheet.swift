import DataKit
import DesignSystem
import SwiftUI

/// Report, and optionally block. GLO-142, `docs/tech/02` §7.
public struct ReportSheet: View {
    @State private var model: ReportModel
    @Environment(\.dismiss) private var dismiss

    public init(
        store: SafetyActionsStore,
        subject: ReportSubject,
        subjectID: UUID? = nil,
        subjectUserID: UUID? = nil
    ) {
        _model = State(wrappedValue: ReportModel(
            store: store, subject: subject, subjectID: subjectID, subjectUserID: subjectUserID
        ))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                if model.sent {
                    confirmation
                } else {
                    header
                    reasons
                    detailField
                    blockOption
                    sendButton
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Toast(message).padding(.bottom, Tokens.Space.s8)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("REPORT").eyebrow()
            Text("what's wrong?")
                .font(Typography.display(Typography.Size.h1))
                .foregroundStyle(Tokens.Ink.primary)
        }
    }

    private var reasons: some View {
        VStack(spacing: Tokens.Space.s2) {
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button { model.choose(reason) } label: {
                    HStack {
                        Text(reason.label)
                            .font(.system(size: Typography.Size.body))
                            .foregroundStyle(Tokens.Ink.primary)
                        Spacer()
                        if model.reason == reason {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Tokens.Cherry.base)
                        }
                    }
                    .padding(Tokens.Space.s3)
                    .background(Tokens.Ground.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var detailField: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("anything else? (optional)")
                .font(.system(size: Typography.Size.meta))
                .foregroundStyle(Tokens.Ink.soft)
            GlossedTextArea(text: $model.detail)
        }
    }

    /// Offered, not assumed. Blocking is the part that acts now, so the person
    /// reporting gets to decide rather than having it done for them.
    @ViewBuilder private var blockOption: some View {
        if model.canBlock {
            GlossedCard {
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    GlossedCheckbox("also block them", isOn: $model.alsoBlock)
                    Text("they won't see you and you won't see them. any follows between you are removed.")
                        .font(.system(size: Typography.Size.meta))
                        .foregroundStyle(Tokens.Ink.faint)
                }
            }
        }
    }

    private var sendButton: some View {
        Button(model.isSending ? "sending…" : "send") {
            Task { await model.send() }
        }
        .buttonStyle(.glossed(.primary, block: true))
        .disabled(!model.canSend)
    }

    /// Says what happened, not what we wish happened.
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            Text(model.didBlock ? "done" : "thanks")
                .font(Typography.display(Typography.Size.h1))
                .foregroundStyle(Tokens.Ink.primary)
            Text(model.outcomeLine)
                .font(.system(size: Typography.Size.body))
                .foregroundStyle(Tokens.Ink.primary)
            Button("close") { dismiss() }
                .buttonStyle(.glossed(.secondary, block: true))
        }
    }
}
