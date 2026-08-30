import DataKit
import DesignSystem
import SwiftUI

/// The handle claim screen. GLO-123, `docs/tech/02` §3.
///
/// Built from the design system (Sean, Aug 29: no frames for 1.5).
public struct HandleClaimView: View {
    @State private var model: HandleClaimModel
    @State private var checkTask: Task<Void, Never>?

    public init(store: HandleStore) {
        _model = State(wrappedValue: HandleClaimModel(store: store))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                header
                if model.claimed == nil {
                    field
                    claimButton
                } else {
                    claimedCard
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

    /// The pop moment: the handle itself, at display size, as it is being typed.
    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("YOUR HANDLE").eyebrow()
            Text(model.typed.isEmpty ? "@yourname" : "@\(model.typed)")
                .font(Typography.display(Typography.Size.h1))
                .foregroundStyle(model.typed.isEmpty ? Tokens.Ink.faint : Tokens.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("this is how people find you. you can't change it later.")
                .font(.system(size: Typography.Size.small))
                .foregroundStyle(Tokens.Ink.soft)
        }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            // Normalising in the binding rather than in `typed`'s didSet:
            // mutating it there leaves TextField's own buffer stale (GLO-183).
            handleField
                .autocorrectionDisabled()
                .onChange(of: model.typed) { _, _ in scheduleCheck() }

            Text(model.helperText)
                .font(.system(size: Typography.Size.meta))
                .foregroundStyle(helperColor)
        }
    }

    /// iOS-only modifier; this package also builds for macOS.
    private var handleField: some View {
        let binding = Binding(
            get: { model.typed },
            set: { model.typed = HandleClaimModel.normalize($0) }
        )
        #if os(iOS)
            return GlossedInput("yourname", text: binding)
                .textInputAutocapitalization(.never)
        #else
            return GlossedInput("yourname", text: binding)
        #endif
    }

    private var helperColor: Color {
        switch model.verdict {
        case .available: Tokens.Support.mint
        case .unavailable, .badCharacters, .tooShort: Tokens.Cherry.deep
        default: Tokens.Ink.faint
        }
    }

    private var claimButton: some View {
        Button(model.isClaiming ? "claiming…" : "claim it") {
            Task { await model.claim() }
        }
        .buttonStyle(.glossed(.primary, block: true))
        .disabled(!model.verdict.isClaimable || model.isClaiming)
    }

    /// The state that has to be honest. A handle is claimed the moment the row
    /// lands, but it renders publicly only once approved — and with moderation
    /// parked nothing approves it. Saying "you're live" here would be the
    /// screen making a promise the system cannot keep.
    private var claimedCard: some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Badge("live", tone: .mint)
                Text(model.claimedText)
                    .font(.system(size: Typography.Size.body))
                    .foregroundStyle(Tokens.Ink.primary)
            }
        }
    }

    /// Debounced so the field does not ask the server on every keystroke.
    private func scheduleCheck() {
        checkTask?.cancel()
        guard model.verdict == .checking else { return }
        // The candidate is captured HERE, at schedule time. Passing it in is
        // what makes the model's staleness guard able to fire at all.
        let candidate = model.typed
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await model.checkAvailability(for: candidate)
        }
    }
}
