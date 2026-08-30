import DesignSystem
import SwiftUI

/// What the host needs to render one side of a comparison.
///
/// Outside `FaceOffView` rather than nested in it: a type nested in a generic
/// is parameterised by that generic, so a host building the card closure could
/// not name the very type the closure has to return.
public struct FaceOffContender: Identifiable, Equatable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// The face-off: two products, one question, no stars anywhere.
///
/// The view owns only presentation — every ordering decision comes from
/// `RankingEngine`, so what a session means is decided by tested logic rather
/// than by whichever branch the UI happened to take.
public struct FaceOffView<Card: View>: View {
    public typealias Contender = FaceOffContender

    let session: FaceOffSession
    let contender: (UUID) -> Contender
    @ViewBuilder let card: (Contender) -> Card
    let onFinished: (FaceOffSession.Outcome) -> Void
    /// The frame's own exit from the done state — `back to shelf`, the only
    /// control on that screen. Without it a finished session is a dead end,
    /// which is how this view has always been (nothing hosted it, so nothing
    /// noticed).
    let onDone: (() -> Void)?
    let doneLabel: String
    /// Set when the write did not land. The placement above it is optimistic —
    /// the same optimism the fit control has — so this is what stops a
    /// celebration standing in for a save that never happened.
    let saveFailure: String?

    @State private var state: FaceOffSession

    public init(
        session: FaceOffSession,
        contender: @escaping (UUID) -> Contender,
        saveFailure: String? = nil,
        doneLabel: String = "back to shelf",
        onDone: (() -> Void)? = nil,
        onFinished: @escaping (FaceOffSession.Outcome) -> Void,
        @ViewBuilder card: @escaping (Contender) -> Card
    ) {
        self.session = session
        self.contender = contender
        self.saveFailure = saveFailure
        self.doneLabel = doneLabel
        self.onDone = onDone
        self.onFinished = onFinished
        self.card = card
        _state = State(initialValue: session)
    }

    public var body: some View {
        VStack(spacing: Tokens.Space.s5) {
            header
            if let comparison = state.currentComparison {
                question(comparison)
            } else {
                result
            }
        }
        .padding(.horizontal, Tokens.Space.s4)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        Badge(
            state.isFinished ? "done" : "face-off \(state.answered + 1) of \(state.estimatedTotal)",
            tone: .lilac
        )
    }

    private func question(_ comparison: RankingEngine.Comparison) -> some View {
        VStack(spacing: Tokens.Space.s5) {
            Text("which do you\nreach for?")
                .font(Typography.display(27))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Tokens.Space.s3) {
                side(comparison.candidate, rotation: Tokens.Rotate.r3, candidateWon: true)
                side(comparison.opponent, rotation: Tokens.Rotate.r2, candidateWon: false)
            }

            Button("too close to call — skip") {
                state.skip()
                finishIfSettled()
            }
            .font(Typography.mono(11.5))
            .foregroundStyle(Tokens.Ink.soft)
            .buttonStyle(.plain)
        }
    }

    private func side(_ itemID: UUID, rotation: Angle, candidateWon: Bool) -> some View {
        let person = contender(itemID)
        return Button {
            state.record(candidateWon: candidateWon)
            finishIfSettled()
        } label: {
            card(person)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Tokens.Space.s4)
                .padding(.horizontal, Tokens.Space.s3)
                .background(Tokens.Ground.card)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
                )
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                        .fill(Tokens.Ink.primary)
                        .offset(x: Tokens.Shadow.lg, y: Tokens.Shadow.lg)
                )
                .rotationEffect(rotation)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I reach for \(person.name)")
    }

    private var result: some View {
        VStack(spacing: Tokens.Space.s3) {
            Text("#\(state.finalPosition)")
                .font(Typography.display(56))
                .foregroundStyle(Tokens.Cherry.base)
            // "in <label>", not the frame's "of 5 blushes". `categories.label`
            // is singular in the database — `blush`, `cleanser` — so the
            // frame's plural cannot be produced from the data, and suffixing
            // one on is wrong the moment the label is `serums + actives`
            // (GLO-203's shape). Driving it showed "of 4 blush" (GLO-250).
            Text("of \(state.finalListLength) in \(state.categoryLabel)").meta()
            if let saveFailure {
                // The placement on screen was optimistic. It did not land, and
                // a toast on top of a failed write would be the app telling
                // someone their answer was recorded when it was not.
                Text(saveFailure).meta()
                Text("your answers are still here — try again in a moment").meta()
            } else if state.isApproximate {
                // A capped placement is our guess, not their answer, so it does
                // not get the celebratory toast.
                Text("we placed it here — rank it again any time to sharpen").meta()
            } else {
                // U+FE0E forces the TEXT presentation. Caveat has no glyph for ✿
                // (GLO-69), so it always falls back — without the selector iOS
                // picks Apple Color Emoji and drops a pink sticker into a
                // monochrome cherry hand line. ImportView fixed this and its
                // comment said the same fix was owed everywhere else; this is
                // that debt (GLO-214).
                Toast("ranked! nice taste ✿\u{FE0E}", hand: true)
            }
            if let onDone {
                Button(doneLabel, action: onDone)
                    .buttonStyle(.plain)
                    .font(Typography.mono(11.5))
                    .foregroundStyle(Tokens.Semantic.accentText)
                    .underline()
                    .padding(.top, Tokens.Space.s2)
            }
        }
    }

    private func finishIfSettled() {
        guard state.isFinished else { return }
        onFinished(state.outcome())
    }
}
