import SwiftUI

/// Platform-neutral keyboard hint (UIKeyboardType is UIKit-only; the package
/// also builds for macOS so tests can run without a simulator).
public enum GlossedKeyboard: Equatable {
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

/// How the keyboard should treat what is typed.
///
/// **`plain` is the default, and that is the whole point of GLO-57.** Left to
/// iOS, a text field capitalises the first letter and autocorrects toward
/// English words — which turns "laneige" into "lineage", misses a product we
/// actually have, and writes the miss to `failed_searches` as demand for
/// something already in the catalog. Every field in this app is a name, a
/// handle, a query or a number; prose is the exception, and the exception is
/// what should have to say so.
///
/// Before this, the choice lived at the call site. Three screens remembered,
/// and the two the ticket predicted would forget had — the create rung's brand
/// typeahead had no protection at all, and linked socials disabled autocorrect
/// but not capitalisation.
public enum GlossedTyping: Equatable {
    /// Names, handles, queries, codes. No capitalisation, no autocorrect.
    case plain
    /// Prose a person writes to be read — a caption, a note, a bio.
    case sentences
}

/// Pill text field: hairline border at rest, ink border + cherry focus ring when
/// active. Lowercase label in mono, per the kit's form voice.
public struct GlossedInput: View {
    let label: String?
    let placeholder: String
    let hint: String?
    @Binding var text: String
    var keyboard: GlossedKeyboard = .text
    var typing: GlossedTyping = .plain

    @FocusState private var focused: Bool

    public init(
        _ placeholder: String,
        text: Binding<String>,
        label: String? = nil,
        hint: String? = nil,
        keyboard: GlossedKeyboard = .text,
        typing: GlossedTyping = .plain
    ) {
        self.placeholder = placeholder
        _text = text
        self.label = label
        self.hint = hint
        self.keyboard = keyboard
        self.typing = typing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            if let label {
                Text(label).meta()
            }
            TextField(placeholder, text: $text)
                .font(Typography.control(Typography.Size.body, weight: .semibold))
                .glossedKeyboard(keyboard)
                .glossedTyping(typing)
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
///
/// Deliberately has no `typing` option: everything that has ever gone in one
/// is prose a person wrote to be read — a caption, a shelf note, a report.
/// `GlossedInput` defaults to `.plain` because its fields are names and
/// queries; this one is the exception the enum's doc comment names, and it
/// stays on the system default.
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

    /// `textInputAutocapitalization` is iOS/tvOS/watchOS-only and these
    /// packages also build for macOS, so the non-UIKit branch stays. macOS has
    /// no autocapitalisation to disable, so `autocorrectionDisabled()` alone is
    /// correct there — not an oversight (GLO-57's own note).
    @ViewBuilder
    func glossedTyping(_ typing: GlossedTyping) -> some View {
        switch typing {
        case .plain:
            #if canImport(UIKit)
                textInputAutocapitalization(.never).autocorrectionDisabled()
            #else
                autocorrectionDisabled()
            #endif
        case .sentences:
            self
        }
    }
}
