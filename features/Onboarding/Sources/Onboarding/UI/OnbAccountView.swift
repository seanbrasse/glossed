import DataKit
import DesignSystem
import SwiftUI

/// `G.OnbAccount` — one decision per screen: method → (phone → code) →
/// birthday, sign-in buttons pinned to the bottom, every screen backs up
/// one. The login mode is this same screen (`mode: .login`), the kit's own
/// ruling, "so the two paths can't drift apart."
public struct OnbAccountView: View {
    @State private var model: AccountModel
    private let quiz: OnboardingModel
    /// Back from the method stage — the caller's screen (payoff / hook).
    private let onExit: () -> Void
    /// The screen's terminal, both modes: the batch write on signup, the
    /// verified login on login. Login used to have none — the returning
    /// user pressed "verify" and stayed on the code boxes.
    private let onCreated: () -> Void

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
        }
    }

    private func title(_ first: String, _ second: String) -> some View {
        Text("\(first)\n\(second)")
            .font(Typography.display(32))
            .tracking(-0.64)
            .foregroundStyle(Tokens.Ink.primary)
            .padding(.vertical, Tokens.Space.s1)
    }

    // MARK: - method

    @ViewBuilder private var methodStage: some View {
        Text("TWO WAYS IN · NOTHING ELSE").eyebrow()
        title("save your", "shelf")
        Text("no email, no password, no third social \u{273F}")
            .handAside()
            .rotationEffect(.degrees(-1))
    }

    // MARK: - phone

    @ViewBuilder private var phoneStage: some View {
        Text("STEP 1 OF 3 · YOUR NUMBER").eyebrow()
        title("what\u{2019}s your", "number?")
        Text("we text a six-digit code — that\u{2019}s the whole login")
            .handAside()
            .rotationEffect(.degrees(-1))
        GlossedInput(
            "+1 555 0134",
            text: Binding(get: { model.phoneNumber }, set: { model.phoneNumber = $0 }),
            label: "phone number",
            keyboard: .phone
        )
        .padding(.top, Tokens.Space.s4)
        Text("never shown to anyone, never used to find you unless you turn that on")
            .meta()
            .padding(.top, Tokens.Space.s2)
    }

    // MARK: - code

    @ViewBuilder private var codeStage: some View {
        Text("STEP 2 OF 3 · VERIFY").eyebrow()
        title("type the", "six digits")
        Text("sent to \(model.phoneNumber.isEmpty ? "your number" : model.phoneNumber) \u{273F}")
            .handAside()
            .rotationEffect(.degrees(-1))
        codeBoxes
            .padding(.top, Tokens.Space.s5)
        HStack(spacing: 14) {
            Button("resend the code") { model.enterCode("") }
                .buttonStyle(.plain)
                .font(Typography.mono())
                .foregroundStyle(Tokens.Semantic.accentText)
                .underline()
            Text("codes arrive within a minute").meta()
        }
        .padding(.top, Tokens.Space.s3)
    }

    private var codeBoxes: some View {
        ZStack {
            HStack(spacing: Tokens.Space.s2) {
                ForEach(0 ..< 6, id: \.self) { index in
                    codeBox(at: index)
                }
            }
            hiddenCodeField
        }
    }

    /// The invisible field the boxes front for — numeric, autofilling from
    /// SMS on iOS; the platform modifiers are iOS-only.
    private var hiddenCodeField: some View {
        let field = TextField("", text: Binding(
            get: { model.codeDigits },
            set: { model.enterCode($0) }
        ))
        .foregroundStyle(.clear)
        .tint(.clear)
        .accessibilityLabel("six-digit code")
        #if os(iOS)
            return field
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
        #else
            return field
        #endif
    }

    private func codeBox(at index: Int) -> some View {
        let digit = model.codeDigits.count > index
            ? String(Array(model.codeDigits)[index]) : ""
        let active = model.codeDigits.count == index
        return Text(digit)
            .font(Typography.display(24))
            .foregroundStyle(Tokens.Ink.primary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(digit.isEmpty ? Tokens.Ground.card : Tokens.Support.mintSoft)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                    .strokeBorder(
                        active || !digit.isEmpty ? Tokens.Ink.primary : Tokens.Ground.line,
                        lineWidth: active || !digit.isEmpty ? Tokens.Border.std : Tokens.Border.hair
                    )
            )
            .animation(Tokens.Motion.pop(), value: model.codeDigits)
    }

    // MARK: - birthday

    @ViewBuilder private var birthdayStage: some View {
        Text(model.method == .phone ? "STEP 3 OF 3 · BIRTHDAY" : "LAST THING · BIRTHDAY").eyebrow()
        title("when\u{2019}s your", "birthday?")
        Text("some products are 18+, and age changes what we recommend")
            .handAside()
            .rotationEffect(.degrees(-1))
        // The native wheel, deliberately — the kit trades its typeface for
        // the control everyone already knows (no typing, no three dropdowns).
        DatePicker(
            "birthday",
            selection: Binding(
                get: { model.birthday ?? AccountModel.birthdayRange.upperBound },
                set: { model.birthday = $0 }
            ),
            in: AccountModel.birthdayRange,
            displayedComponents: .date
        )
        #if os(iOS)
        .datePickerStyle(.wheel)
        #endif
        .labelsHidden()
        .padding(.top, Tokens.Space.s2)
        Text(model.birthdayEcho() ?? "one spin of the wheel — the native picker, no typing")
            .meta()
        Text("never shown on your profile, never used for anything but the 18+ gate and recommendations")
            .meta()
            .padding(.vertical, 10)
            .padding(.horizontal, Tokens.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Ground.milk)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                    .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
            )
        if let error = model.ageError {
            AgeRefusal(error: error)
        }
        if let error = model.creationError {
            Text(error.userMessage).meta()
        }
    }

    /// Login's terminal, read straight off the model. Signup never sets it —
    /// that path ends at the batch write, birthday gate and all.
    private func landIfAuthenticated() {
        guard model.isAuthenticated else { return }
        onCreated()
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
                Button(model.isCreating ? "creating…" : "create account") {
                    model.createAccount(quiz: quiz, onCreated: onCreated)
                }
                .buttonStyle(.glossed(block: true))
                .disabled(!model.birthdayChosen || model.isCreating)
                Text(model.birthdayChosen
                    ? "that\u{2019}s everything — no email, no password"
                    : "pick a date to continue")
                    .meta()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, Tokens.Space.s3)
    }
}
