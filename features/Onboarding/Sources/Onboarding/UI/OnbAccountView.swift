import DataKit
import DesignSystem
import SwiftUI

/// `G.OnbAccount` — one decision per screen: method → (phone → code) →
/// birthday, sign-in buttons pinned to the bottom, every screen backs up
/// one. The login mode is this same screen (`mode: .login`), the kit's own
/// ruling, "so the two paths can't drift apart."
public struct OnbAccountView: View {
    /// Internal, not private: the five stage bodies live in
    /// `OnbAccountStages.swift` and an extension in another file cannot see
    /// a private member. Same reason `AppShell.tab` is.
    @State var model: AccountModel
    let quiz: OnboardingModel
    /// Back from the method stage — the caller's screen (payoff / hook).
    let onExit: () -> Void
    /// The screen's terminal, both modes: the batch write on signup, the
    /// verified login on login. Login used to have none — the returning
    /// user pressed "verify" and stayed on the code boxes.
    let onCreated: () -> Void

    public init(
        model: AccountModel,
        quiz: OnboardingModel,
        onExit: @escaping () -> Void,
        onCreated: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.quiz = quiz
        self.onExit = onExit
        self.onCreated = onCreated
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    backLink
                    stageBody
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(.init(top: 18, leading: 22, bottom: 22, trailing: 22))
        .background(Tokens.Ground.milk)
    }

    private var backLink: some View {
        Button("← back") {
            if !model.back() {
                onExit()
            }
        }
        .buttonStyle(.plain)
        .font(Typography.mono(12))
        .foregroundStyle(Tokens.Semantic.accentText)
        .underline()
    }

    @ViewBuilder private var stageBody: some View {
        switch model.stage {
        case .method: methodStage
        case .phone: phoneStage
        case .code: codeStage
        case .birthday: birthdayStage
        case .name: nameStage
        }
    }

    func title(_ first: String, _ second: String) -> some View {
        Text("\(first)\n\(second)")
            .font(Typography.display(32))
            .tracking(-0.64)
            .foregroundStyle(Tokens.Ink.primary)
            .padding(.vertical, Tokens.Space.s1)
    }

    // MARK: - footer (pinned, the kit's rule)

    private var footer: some View {
        VStack(spacing: Tokens.Space.s2) {
            switch model.stage {
            case .method:
                Button {
                    model.chooseApple()
                    landIfAuthenticated()
                } label: {
                    Label("sign in with apple", systemImage: "apple.logo")
                }
                .buttonStyle(.glossed(block: true))
                Button {
                    model.choosePhone()
                } label: {
                    Label("continue with phone number", systemImage: "phone")
                }
                .buttonStyle(.glossed(.secondary, block: true))
                Text("your anchor and fit are saved on this phone already — signing in just keeps them")
                    .meta()
                    .frame(maxWidth: .infinity)
            case .phone:
                Button("text me the code") { model.sendCode() }
                    .buttonStyle(.glossed(block: true))
                    .disabled(!model.canSendCode)
                Text(model.canSendCode ? "standard rates apply" : "enter a number to continue")
                    .meta()
                    .frame(maxWidth: .infinity)
            case .code:
                Button("verify") {
                    model.verifyCode()
                    landIfAuthenticated()
                }
                .buttonStyle(.glossed(block: true))
                .disabled(!model.canVerify)
                Button("wrong number? change it →") { _ = model.back() }
                    .buttonStyle(.plain)
                    .font(Typography.mono())
                    .foregroundStyle(Tokens.Ink.soft)
                    .underline()
            case .birthday:
                Button("continue") { model.birthdayContinued() }
                    .buttonStyle(.glossed(block: true))
                    .disabled(!model.birthdayChosen)
                Text(model.birthdayChosen
                    ? "one more — what should we call you?"
                    : "pick a date to continue")
                    .meta()
                    .frame(maxWidth: .infinity)
            case .name:
                Button(model.isCreating ? "creating…" : "create account") {
                    model.createAccount(quiz: quiz, onCreated: onCreated)
                }
                .buttonStyle(.glossed(block: true))
                .disabled(!model.canCreate || model.isCreating)
                Text(model.canCreate
                    ? "that\u{2019}s everything — no email, no password"
                    : "a name to continue")
                    .meta()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, Tokens.Space.s3)
    }
}
