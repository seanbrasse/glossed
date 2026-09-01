import DataKit
import DesignSystem
import SwiftUI

// The account walk's five stage bodies, lifted out of `OnbAccountView.swift`
// when the name stage (GLO-245, Sean's "nobody gets through onboarding without
// a handle") took that file past SwiftLint's 300-line and 250-line type-body
// ceilings. The house remedy is to extract rather than trim the explanation —
// the same move `AppShellTabs` and `ShelfModels` made.

extension OnbAccountView {
    // MARK: - method

    @ViewBuilder var methodStage: some View {
        Text("TWO WAYS IN · NOTHING ELSE").eyebrow()
        title("save your", "shelf")
        Text("no email, no password, no third social \u{273F}")
            .handAside()
            .rotationEffect(.degrees(-1))
    }

    // MARK: - phone

    @ViewBuilder var phoneStage: some View {
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

    @ViewBuilder var codeStage: some View {
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

    func codeBox(at index: Int) -> some View {
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

    @ViewBuilder var birthdayStage: some View {
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
    func landIfAuthenticated() {
        guard model.isAuthenticated else { return }
        onCreated()
    }

    // MARK: - name

    /// **The one thing onboarding never asked for.** `ProfileDraft` has always
    /// carried `displayName` and nothing set it, so a brand-new profile led
    /// with a blank — and since #410 made the display name the h1, it fell
    /// back to printing the handle twice.
    ///
    /// It is asked here rather than in the quiz because it rides the same
    /// write, and after the birthday because the age gate should refuse an
    /// under-13 at the question that decides it, not two screens later.
    var nameStage: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("ONE MORE · YOUR NAME").eyebrow()
            title("what should", "we call you?")
            Text("this is the name on your profile. your handle comes next.")
                .font(Typography.hand())
                .foregroundStyle(Tokens.Semantic.accentText)
            GlossedInput(
                "maya",
                text: Binding(get: { model.displayName }, set: { model.displayName = $0 }),
                label: "name"
            )
            Text("you can change it any time in settings.").meta()
            if let error = model.ageError {
                Text(error.userMessage).meta()
            }
        }
    }
}
