import SwiftUI

/// 1a–4c, the community's own vocabulary. Unlike skin tone this is asked
/// directly, because hair has no anchor product to infer it from.
public struct HairTypePicker: View {
    @Binding var selection: String?

    public init(selection: Binding<String?>) {
        _selection = selection
    }

    private let groups: [(title: String, patterns: [String])] = [
        ("1 · straight", ["1a", "1b", "1c"]),
        ("2 · wavy", ["2a", "2b", "2c"]),
        ("3 · curly", ["3a", "3b", "3c"]),
        ("4 · coily", ["4a", "4b", "4c"])
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    Text(group.title).eyebrow()
                    HStack(spacing: Tokens.Space.s2) {
                        ForEach(group.patterns, id: \.self) { pattern in
                            cell(pattern)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ pattern: String) -> some View {
        let isOn = selection == pattern
        return Button { selection = pattern } label: {
            VStack(spacing: 4) {
                // The strand for this pattern (GLO-248): ink strokes on the
                // tile's own milk, drawn rather than photographed — Sean's
                // call, Sep 2, and the same hand as `ProductMock`. Twelve
                // generated from one script (`Resources/hair-strands.py`) so
                // they share one stroke-weight ramp and get tighter every
                // row. PRD §06's trust note still stands over the 4-series:
                // people with 4a–4c hair review those three before they are
                // treated as settled — the drawings are a starting point.
                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                    .fill(Tokens.Ground.milk)
                    .frame(height: 64)
                    .overlay(
                        Image("hair-\(pattern)", bundle: .module)
                            .resizable()
                            .scaledToFit()
                            .padding(2)
                            .accessibilityHidden(true)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.md)
                            .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
                    )
                Text(pattern).font(Typography.mono(11, bold: isOn))
            }
            .padding(4)
            .background(isOn ? Tokens.Cherry.soft : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                    .strokeBorder(isOn ? Tokens.Ink.primary : .clear, lineWidth: Tokens.Border.std)
            )
            // The unselected cell's background is `.clear`, and a plain
            // button does not hit-test clear pixels — the target was the
            // swatch and the code, with a dead gap between and around them.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("hair type \(pattern)")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Suggests a category the user has none of. Framed as what people like you
/// keep — never as what you lack, which in this category is one degree from
/// telling someone their routine is inadequate.
public struct GapCard: View {
    public enum DismissReason: String, CaseIterable, Sendable {
        case alreadyHaveOne, notInterested, tooExpensive, useSomethingElse

        public var label: String {
            switch self {
            case .alreadyHaveOne: "already have one"
            case .notInterested: "not interested"
            case .tooExpensive: "too expensive"
            case .useSomethingElse: "i use something else"
            }
        }
    }

    let title: String
    let subtitle: String
    let peopleCount: Int
    let onAccept: () -> Void
    let onDismiss: (DismissReason) -> Void

    @State private var showingReasons = false

    public init(
        title: String,
        subtitle: String,
        peopleCount: Int,
        onAccept: @escaping () -> Void,
        onDismiss: @escaping (DismissReason) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.peopleCount = peopleCount
        self.onAccept = onAccept
        self.onDismiss = onDismiss
    }

    public var body: some View {
        GlossedCard(tint: .butter) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text(title).font(Typography.display(17, weight: 700))
                Text(subtitle).meta()
                EvidenceLine(n: peopleCount, label: "people in your shade keep one", tone: .ink)

                if showingReasons {
                    // The reason is the point: a rejection teaches us nothing,
                    // a reason feeds the catalog, the price band, or a real gap.
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        Text("WHY NOT?").eyebrow()
                        ForEach(DismissReason.allCases, id: \.self) { reason in
                            Button { onDismiss(reason) } label: {
                                Text(reason.label)
                                    .font(Typography.control(13, weight: .semibold))
                                    .foregroundStyle(Tokens.Ink.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(minHeight: Tokens.hitTarget)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    HStack(spacing: Tokens.Space.s3) {
                        Button("show me", action: onAccept)
                            .buttonStyle(.glossed(.primary, size: .sm))
                        Button("not now") { showingReasons = true }
                            .buttonStyle(.glossed(.secondary, size: .sm))
                    }
                }
            }
        }
        .animation(Tokens.Motion.pop(Tokens.Motion.med), value: showingReasons)
    }
}
