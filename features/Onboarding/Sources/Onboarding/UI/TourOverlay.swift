import DesignSystem
import SwiftUI

/// `G.OnbTour`'s chrome: the scrim, the pop card, the dots, and the
/// pointing finger. The app composes this OVER its real tabs — the overlay
/// owns no screens and no nav; it is handed the x-center of the tab the
/// slide points at (`anchorX`, in the overlay's own coordinate space)
/// because only the shell knows its nav's geometry. Nil anchors draw no
/// arrow and no ring rather than a guess.
public struct TourOverlay: View {
    @State private var model: TourModel
    private let anchorX: (String) -> CGFloat?
    private let onTabChange: (String) -> Void
    private let onDone: () -> Void

    public init(
        model: TourModel,
        anchorX: @escaping (String) -> CGFloat?,
        onTabChange: @escaping (String) -> Void,
        onDone: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.anchorX = anchorX
        self.onTabChange = onTabChange
        self.onDone = onDone
    }

    public var body: some View {
        ZStack {
            // The scrim: the real screen stays visible underneath, dimmed —
            // the tour shows the app, it does not replace it.
            Tokens.Ink.primary.opacity(0.5)
                .ignoresSafeArea()
            card
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 18)
                .padding(.top, 110)
            if let x = anchorX(model.slide.tab) {
                pointer(at: x)
            }
        }
        .onAppear { onTabChange(model.slide.tab) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("THE TOUR · \(model.stepIndex + 1) OF \(TourModel.slides.count)")
                .eyebrow(color: Tokens.Semantic.accentText)
            Text(model.slide.title)
                .font(Typography.display(30))
                .tracking(-0.6)
                .foregroundStyle(Tokens.Ink.primary)
            Text(model.slide.story)
                .handAside()
                .rotationEffect(.degrees(-0.5))
            dots
                .padding(.vertical, Tokens.Space.s2)
            HStack(spacing: 14) {
                Button(model.nextLabel) {
                    if model.next() {
                        onTabChange(model.slide.tab)
                    } else {
                        onDone()
                    }
                }
                .buttonStyle(.glossed())
                Button("skip tour", action: onDone)
                    .buttonStyle(.plain)
                    .font(Typography.mono())
                    .foregroundStyle(Tokens.Ink.soft)
                    .underline()
            }
        }
        .padding(.init(top: 18, leading: 18, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        )
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.xl, y: Tokens.Shadow.xl)
        )
        .animation(Tokens.Motion.pop(Tokens.Motion.med), value: model.stepIndex)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< TourModel.slides.count, id: \.self) { index in
                Capsule()
                    .fill(index == model.stepIndex ? Tokens.Cherry.base : Tokens.Ground.line)
                    .frame(width: index == model.stepIndex ? 18 : 7, height: 7)
            }
        }
        .animation(Tokens.Motion.pop(), value: model.stepIndex)
    }

    /// The bouncing arrow and pulsing ring over the slide's tab — one
    /// 54pt column so the two share a center exactly (the first cut gave
    /// the arrow its own magic offset, and the two visibly disagreed).
    private func pointer(at x: CGFloat) -> some View {
        VStack(spacing: Tokens.Space.s2) {
            Spacer()
            TourArrow()
            PulsingRing()
                .padding(.bottom, 14)
        }
        .frame(width: 54)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(x: x - 27)
        .allowsHitTesting(false)
        .animation(Tokens.Motion.pop(Tokens.Motion.med), value: x)
    }
}

/// The "look down here" arrow, bouncing on its own clock.
private struct TourArrow: View {
    @State private var up = false

    var body: some View {
        Text("↓")
            .font(Typography.display(30))
            .foregroundStyle(.white)
            .shadow(color: Tokens.Ink.primary, radius: 0, x: 2, y: 2)
            .offset(y: up ? -6 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
    }
}

/// The kit's `tourPulse`: the ring breathes outward and fades, forever —
/// a still circle reads as a mistake where a pulse reads as a pointer.
private struct PulsingRing: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .strokeBorder(Tokens.Cherry.base, lineWidth: 2.5)
            .frame(width: 54, height: 54)
            .scaleEffect(pulsing ? 1.25 : 0.92)
            .opacity(pulsing ? 0.25 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}
