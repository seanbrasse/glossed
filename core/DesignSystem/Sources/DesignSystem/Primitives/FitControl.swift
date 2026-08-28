import SwiftUI

/// The six fit answers, in the order the kit shows them.
///
/// DesignSystem is standalone by design, so these are declared here rather than
/// imported from the data layer. The feature that persists a fit maps this to
/// its own type with an exhaustive switch — which makes the compiler, not a
/// test, the thing that catches a divergence.
public enum FitAnswer: String, CaseIterable, Sendable {
    case justRight, tooLight, tooDark, tooPink, tooYellow, tooOrange

    public var label: String {
        switch self {
        case .justRight: "just right"
        case .tooLight: "too light"
        case .tooDark: "too dark"
        case .tooPink: "too pink"
        case .tooYellow: "too yellow"
        case .tooOrange: "too orange"
        }
    }

    /// A miss is not a failure — it bounds where someone's skin sits, which is
    /// half the signal. The copy has to make that safe to admit.
    public var isMatch: Bool {
        self == .justRight
    }
}

/// Asked on every log of an anchor-category product, not buried in a rating
/// flow: most people log in five seconds and never rank.
public struct FitControl: View {
    @Binding var selection: FitAnswer?
    let note: String?

    public init(selection: Binding<FitAnswer?>, note: String? = "we only match shades people have actually worn") {
        _selection = selection
        self.note = note
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("DID THE SHADE FIT?").eyebrow()
            LazyVGrid(columns: columns, spacing: Tokens.Space.s2) {
                ForEach(FitAnswer.allCases, id: \.self) { answer in
                    answerButton(answer)
                }
            }
            if let note {
                Text(note).meta()
            }
        }
    }

    private func answerButton(_ answer: FitAnswer) -> some View {
        let isOn = selection == answer
        return Button {
            selection = isOn ? nil : answer
        } label: {
            Text(answer.label)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(Tokens.Ink.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 38)
                .background(isOn ? (answer.isMatch ? Tokens.Support.mintSoft : Tokens.Cherry.soft) : Tokens.Ground.card)
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

/// How much of a match is earned so far. Framed as a promise — "this gets
/// sharper as you add products" — never as an apology for being incomplete.
public struct ConfidenceMeter: View {
    let have: Int
    let need: Int

    public init(have: Int, need: Int) {
        self.have = have
        self.need = need
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Tokens.Space.s2) {
                Text("match confidence").meta()
                Spacer(minLength: 0)
                Text("\(min(have, need)) of \(need) anchors").meta()
            }
            HStack(spacing: 4) {
                ForEach(0 ..< max(need, 1), id: \.self) { index in
                    Capsule()
                        .fill(index < have ? Tokens.Cherry.base : Tokens.Ground.line)
                        .frame(height: 5)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("match confidence, \(min(have, need)) of \(need) anchors")
    }
}
