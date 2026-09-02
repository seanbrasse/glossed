import DataKit
import DesignSystem
import SwiftUI

/// `G.OnbQuiz` — the reordered quiz: what you buy → the anchor → the two
/// conditional branches. One question per screen, a progress bar that
/// grows when a branch joins, and every step backs up one.
public struct OnbQuizView: View {
    @State private var model: OnboardingModel
    /// The anchor step's brands, supplied by the app (the picker renders
    /// whatever it is handed; an empty catalog renders the no-foundation
    /// path alone rather than an empty wall of pills).
    private let anchorCatalog: [ShadeAnchorPicker.BrandEntry]
    /// Back off the first question. Nil hides the link there — a caller
    /// with nowhere to send the user (the debug catalog) shows no door.
    private let onExit: (() -> Void)?
    private let onFinished: () -> Void

    public init(
        model: OnboardingModel,
        anchorCatalog: [ShadeAnchorPicker.BrandEntry],
        onExit: (() -> Void)? = nil,
        onFinished: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.anchorCatalog = anchorCatalog
        self.onExit = onExit
        self.onFinished = onFinished
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            progressBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    question
                    answerArea
                        .padding(.vertical, Tokens.Space.s5)
                }
            }
            footer
        }
        .padding(.init(top: 18, leading: 22, bottom: 22, trailing: 22))
        .background(Tokens.Ground.milk)
        .onChange(of: model.step, initial: true) { _, _ in model.recordViewed() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("STEP \(min(model.stepIndex, model.steps.count - 1) + 1) OF \(model.steps.count) · JUST TAPS")
                .eyebrow()
            Spacer(minLength: 0)
            // Every step backs up one; the first backs out to the start
            // screen (Sean, Sep 2: "go back throughout onboarding").
            if !model.isFirstStep || onExit != nil {
                Button("back") {
                    if model.isFirstStep {
                        onExit?()
                    } else {
                        model.back()
                    }
                }
                .buttonStyle(.textLink(Tokens.Ink.soft, size: 11))
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(Array(model.steps.enumerated()), id: \.element) { index, _ in
                Capsule()
                    .fill(index <= model.stepIndex ? Tokens.Cherry.base : Tokens.Ground.line)
                    .frame(height: 4)
            }
        }
        .padding(.top, 10)
        .animation(Tokens.Motion.pop(), value: model.steps)
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Text(OnboardingModel.question(for: model.step).joined(separator: "\n"))
                .font(Typography.display(32))
                .tracking(-0.64)
                .lineSpacing(0)
                .foregroundStyle(Tokens.Ink.primary)
                .padding(.top, 14)
            Text(OnboardingModel.aside(for: model.step))
                .handAside()
                .rotationEffect(.degrees(-1))
        }
    }

    @ViewBuilder private var answerArea: some View {
        switch model.step {
        case .domains:
            domainsGrid
        case .anchor:
            anchorStep
        case .hair:
            HairTypePicker(
                selection: Binding(get: { model.hairPattern }, set: { model.hairPattern = $0 })
            )
        case .tone:
            toneStep
        }
    }

    // MARK: - domains

    private var domainsGrid: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Domain.allCases, id: \.self) { domain in
                    domainCard(domain)
                }
            }
            HStack(spacing: Tokens.Space.s3) {
                Button("i buy all four →") { model.selectAllDomains() }
                    .buttonStyle(.textLink)
                Text("\(model.domains.count) of 4 · at least one").meta()
            }
        }
    }

    private func domainCard(_ domain: Domain) -> some View {
        let on = model.domains.contains(domain)
        return Button {
            model.toggle(domain)
        } label: {
            Text(domain.rawValue)
                .font(Typography.display(16, weight: 700))
                .foregroundStyle(Tokens.Ink.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                // A plain-styled button hit-tests its label's opaque
                // content, and the tile is drawn on the button, outside the
                // label — so without this the target was the word "makeup",
                // not the card around it (Sean, Sep 2: "hard to press").
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(on ? Tokens.Cherry.soft : Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(
                    on ? Tokens.Ink.primary : Tokens.Ground.line,
                    lineWidth: on ? Tokens.Border.std : Tokens.Border.hair
                )
        )
        .overlay(alignment: .topTrailing) {
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Tokens.Ink.primary)
                    .frame(width: 18, height: 18)
                    .background(Tokens.Ground.card)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin))
                    .padding(7)
            }
        }
        .rotationEffect(.degrees(on ? -1 : 0))
        .animation(Tokens.Motion.pop(), value: on)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: - anchor

    private var anchorStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !anchorCatalog.isEmpty {
                ShadeAnchorPicker(
                    catalog: anchorCatalog,
                    toneBand: model.toneIndex.map { $0 + 1 },
                    selection: Binding(get: { model.anchor }, set: { model.anchor = $0 })
                )
            }
            Button("i don\u{2019}t wear any foundation →") { model.setNoFoundation() }
                .buttonStyle(.textLink)
            if model.noFoundation {
                Text("no problem — we\u{2019}ll ask for your tone band instead, and sharpen it as you rank")
                    .meta()
                    .padding(.vertical, 10)
                    .padding(.horizontal, Tokens.Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tokens.Support.butterSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.md)
                            .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
                    )
            }
        }
    }

    // MARK: - tone

    private var toneStep: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                ForEach(Array(OnboardingModel.toneSwatches.enumerated()), id: \.offset) { index, hex in
                    toneSwatch(index: index, hex: hex)
                }
            }
            Text("a starting point — matches sharpen as we learn which products you love").meta()
        }
    }

    private func toneSwatch(index: Int, hex: UInt32) -> some View {
        let on = model.toneIndex == index
        return Button {
            model.toneIndex = index
        } label: {
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .fill(Color(hexValue: hex))
                .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(
                    on ? Tokens.Ink.primary : Tokens.Ground.line,
                    lineWidth: on ? 2.5 : Tokens.Border.hair
                )
        )
        .rotationEffect(.degrees(on ? -3 : 0))
        .scaleEffect(on ? 1.06 : 1)
        .animation(Tokens.Motion.pop(), value: on)
        .accessibilityLabel("tone \(index + 1)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: - footer

    private var footer: some View {
        VStack(spacing: Tokens.Space.s2) {
            Button("continue") {
                if !model.next() {
                    onFinished()
                }
            }
            .buttonStyle(.glossed(block: true))
            Text("skin type, concerns and brands come after you\u{2019}re in")
                .meta()
                .frame(maxWidth: .infinity)
        }
        .padding(.top, Tokens.Space.s3)
    }
}
