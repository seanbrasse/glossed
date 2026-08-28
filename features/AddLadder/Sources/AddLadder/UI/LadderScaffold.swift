import DesignSystem
import SwiftUI

/// The chrome every rung shares: a way back, the title, and the rail.
///
/// Built to `G.AddLadder` in the kit's `screens.jsx`. Each rung renders its own
/// body inside this; nothing about the frame is decided per-rung.
public struct LadderScaffold<Content: View>: View {
    private let ladder: Ladder
    private let onBack: () -> Void
    @ViewBuilder private let content: () -> Content

    public init(
        ladder: Ladder,
        onBack: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.ladder = ladder
        self.onBack = onBack
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("← back", action: onBack)
                .buttonStyle(.plain)
                .font(Typography.mono(12))
                .foregroundStyle(Tokens.Semantic.accentText)
                .underline()

            Text("add a product")
                .font(Typography.display(28))
                .tracking(-0.56)
                .lineSpacing(0)
                .foregroundStyle(Tokens.Ink.primary)

            LadderRail(rung: ladder.rung)
            content()
        }
        // 110pt of bottom room: the floating nav sits over this screen, and a
        // list that ends underneath it looks like a list that got cut off.
        .padding(.init(top: 14, leading: 16, bottom: 110, trailing: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.Ground.milk)
    }
}

/// Four segments, always all four, filling as you go.
///
/// Not a breadcrumb: the kit shows the whole ladder from the first rung, so
/// someone deciding whether to keep going can see how much is left. Rendering
/// only the rungs already visited — which is what this used to do — hides the
/// one thing the rail is for.
struct LadderRail: View {
    let rung: Rung

    /// `confirm` is not a rung on the rail; arriving there leaves `create it`
    /// filled and current, which is where the user actually is.
    static let railRungs: [Rung] = [.search, .barcode, .nearMatches, .create]

    static func label(for rung: Rung) -> String {
        switch rung {
        case .search: "search"
        case .barcode: "scan"
        case .nearMatches: "near matches"
        case .create, .confirm: "create it"
        }
    }

    /// Index on the rail, clamped so `confirm` reads as the last segment.
    static func position(of rung: Rung) -> Int {
        railRungs.firstIndex(of: rung) ?? railRungs.count - 1
    }

    static func isFilled(_ segment: Int, at rung: Rung) -> Bool {
        segment <= position(of: rung)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(LadderRail.railRungs.enumerated()), id: \.element) { index, segment in
                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(
                            LadderRail.isFilled(index, at: rung)
                                ? Tokens.Cherry.base
                                : Tokens.Ground.line
                        )
                        .frame(height: 4)
                    Text(LadderRail.label(for: segment))
                        .font(Typography.mono(9))
                        .kerning(0.54)
                        .foregroundStyle(
                            index == LadderRail.position(of: rung)
                                ? Tokens.Ink.primary
                                : Tokens.Ink.faint
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "step \(LadderRail.position(of: rung) + 1) of \(LadderRail.railRungs.count), \(LadderRail.label(for: rung))"
        )
    }
}
