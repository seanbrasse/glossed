import SwiftUI

/// A two-answer question that you are allowed not to have answered.
///
/// Built for "would you buy it again?" (GLO-87) but deliberately knows nothing
/// about repurchase: the shelf owns that vocabulary, this owns the shape.
///
/// The reason it is not `Segmented` — which the status row next to it uses —
/// is the third state. `Segmented` always has exactly one option selected,
/// which is right for a status (an item is always *something*) and wrong for a
/// question (you may simply not have said). Nil here is unanswered, it renders
/// as neither option filled, and tapping the selected answer returns to it.
///
/// The visual language is `FitControl`'s, for the obvious reason that the two
/// sit inches apart in the same sheet: capsule, bold 12.5, mint for the
/// affirmative and cherry for the negative, hairline until chosen.
public struct YesNoControl: View {
    private let question: String
    private let yesLabel: String
    private let noLabel: String
    @Binding private var selection: Bool?

    public init(
        question: String,
        yes: String = "yes",
        no: String = "no",
        selection: Binding<Bool?>
    ) {
        self.question = question
        yesLabel = yes
        noLabel = no
        _selection = selection
    }

    /// Tapping the chosen answer clears it. Kept `nonisolated` and separate
    /// from the view so the rule can be tested without a main-actor test —
    /// the `FitControl.picked` precedent.
    public nonisolated static func picked(_ answer: Bool, from selection: Bool?) -> Bool? {
        selection == answer ? nil : answer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text(question).eyebrow()
            HStack(spacing: Tokens.Space.s2) {
                answerButton(true, label: yesLabel)
                answerButton(false, label: noLabel)
            }
        }
    }

    private func answerButton(_ answer: Bool, label: String) -> some View {
        let isOn = selection == answer
        return Button {
            selection = YesNoControl.picked(answer, from: selection)
        } label: {
            Text(label)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Tokens.Ink.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 38)
                .background(isOn ? (answer ? Tokens.Support.mintSoft : Tokens.Cherry.soft) : Tokens.Ground.card)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? Tokens.Ink.primary : Tokens.Ground.line,
                        lineWidth: isOn ? Tokens.Border.std : Tokens.Border.hair
                    )
                )
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.pop(), value: isOn)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
