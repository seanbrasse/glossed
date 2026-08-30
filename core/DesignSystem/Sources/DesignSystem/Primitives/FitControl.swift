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

    /// Which axis an answer sits on. Lightness and undertone are independent —
    /// a shade can miss on both — which is why the control holds a set with
    /// one answer per axis rather than a single value (GLO-67). Mirrors the
    /// database's `fit_axis()`; the pgTAP suite pins that side.
    public var axis: FitAxis {
        switch self {
        case .justRight: .justRight
        case .tooLight, .tooDark: .depth
        case .tooPink, .tooYellow, .tooOrange: .undertone
        }
    }
}

/// The three axes a fit answer can sit on.
public enum FitAxis: Sendable {
    case justRight, depth, undertone
}

/// Asked on every log of an anchor-category product, not buried in a rating
/// flow: most people log in five seconds and never rank.
///
/// A set, with the kit's own rules — encoded once in `picked(_:from:)` so the
/// view is just the drawing of it.
public struct FitControl: View {
    @Binding var selection: Set<FitAnswer>
    let note: String?

    public init(selection: Binding<Set<FitAnswer>>, note: String? = "we only match shades people have actually worn") {
        _selection = selection
        self.note = note
    }

    /// The kit's pick rules, verbatim from `glossed-lib.js`:
    /// tapping a selected answer clears it; `just right` is exclusive; any
    /// other answer replaces its axis-mate and clears `just right`.
    ///
    /// `nonisolated`: it is arithmetic on a set, and View conformance would
    /// otherwise pull it onto the main actor — which is also what lets the
    /// rule be tested without a @MainActor test (the `ShelfModel.ordered`
    /// precedent).
    nonisolated static func picked(_ answer: FitAnswer, from selection: Set<FitAnswer>) -> Set<FitAnswer> {
        if selection.contains(answer) {
            return selection.subtracting([answer])
        }
        if answer.isMatch {
            return [answer]
        }
        return selection
            .filter { !$0.isMatch && $0.axis != answer.axis }
            .union([answer])
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
        let isOn = selection.contains(answer)
        return Button {
            selection = FitControl.picked(answer, from: selection)
        } label: {
            Text(answer.label)
                .font(Typography.control(12.5))
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
