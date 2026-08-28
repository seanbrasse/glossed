import SwiftUI

/// Platform-neutral keyboard hint (UIKeyboardType is UIKit-only; the package
/// also builds for macOS so tests can run without a simulator).
public enum GlossedKeyboard {
    case text, phone, numeric, email

    #if canImport(UIKit)
        var uiKit: UIKeyboardType {
            switch self {
            case .text: .default
            case .phone: .phonePad
            case .numeric: .numberPad
            case .email: .emailAddress
            }
        }
    #endif
}

/// Pill text field: hairline border at rest, ink border + cherry focus ring when
/// active. Lowercase label in mono, per the kit's form voice.
public struct GlossedInput: View {
    let label: String?
    let placeholder: String
    let hint: String?
    @Binding var text: String
    var keyboard: GlossedKeyboard = .text

    @FocusState private var focused: Bool

    public init(
        _ placeholder: String,
        text: Binding<String>,
        label: String? = nil,
        hint: String? = nil,
        keyboard: GlossedKeyboard = .text
    ) {
        self.placeholder = placeholder
        _text = text
        self.label = label
        self.hint = hint
        self.keyboard = keyboard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            if let label {
                Text(label).meta()
            }
            TextField(placeholder, text: $text)
                .font(.system(size: Typography.Size.body, weight: .semibold))
                .glossedKeyboard(keyboard)
                .focused($focused)
                .padding(.horizontal, Tokens.Space.s4)
                .frame(minHeight: Tokens.hitTarget)
                .background(Tokens.Ground.card)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        focused ? Tokens.Ink.primary : Tokens.Ground.line,
                        lineWidth: focused ? Tokens.Border.std : Tokens.Border.hair
                    )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Tokens.Cherry.base, lineWidth: focused ? 2 : 0)
                        .padding(-3)
                )
                .animation(Tokens.Motion.pop(), value: focused)
            if let hint {
                Text(hint).meta()
            }
        }
    }
}

/// Multi-line variant for notes and paste-in flows — pop layer (ink + shadow),
/// because typing into it is an interaction.
public struct GlossedTextArea: View {
    let label: String?
    @Binding var text: String
    var minHeight: CGFloat = 96

    public init(text: Binding<String>, label: String? = nil, minHeight: CGFloat = 96) {
        _text = text
        self.label = label
        self.minHeight = minHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            if let label {
                Text(label).meta()
            }
            TextEditor(text: $text)
                .font(Typography.mono(12))
                .scrollContentBackground(.hidden)
                .padding(Tokens.Space.s3)
                .frame(minHeight: minHeight)
                .background(Tokens.Ground.card)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
                )
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .fill(Tokens.Ink.primary)
                        .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
                )
        }
    }
}

private extension View {
    /// Applies the keyboard hint where UIKit provides one; a no-op elsewhere.
    @ViewBuilder
    func glossedKeyboard(_ keyboard: GlossedKeyboard) -> some View {
        #if canImport(UIKit)
            keyboardType(keyboard.uiKit)
        #else
            self
        #endif
    }
}
