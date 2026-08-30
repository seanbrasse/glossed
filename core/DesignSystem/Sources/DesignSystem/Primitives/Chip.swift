import SwiftUI

/// The signature primitive. Two kinds of information, three visual kinds:
/// like (mint fill, + glyph) · dislike (cherry fill, − glyph) · attribute
/// (white fill, lilac dot, · glyph). The glyph carries polarity without color
/// (a11y — decisions log). Every claim chip can carry its count: the receipt.
public struct Chip: View {
    public enum Kind {
        case like, dislike, attribute

        var fill: Color {
            switch self {
            case .like: Tokens.Semantic.likeSoft
            case .dislike: Tokens.Semantic.dislikeSoft
            case .attribute: Tokens.Ground.card
            }
        }

        var dot: Color {
            switch self {
            case .like: Tokens.Semantic.like
            case .dislike: Tokens.Semantic.dislike
            case .attribute: Tokens.Semantic.attribute
            }
        }

        public var glyph: String {
            switch self {
            case .like: "+"
            case .dislike: "\u{2212}"
            case .attribute: "\u{00B7}"
            }
        }
    }

    public enum ChipSize {
        case sm, md
        var font: CGFloat {
            self == .sm ? 12 : 13
        }

        var vertical: CGFloat {
            self == .sm ? 4 : 6
        }
    }

    let label: String
    let kind: Kind
    let size: ChipSize
    let count: String?
    let week: Int?
    let rotation: Angle
    let selected: Bool
    let action: (() -> Void)?

    public init(
        _ label: String, kind: Kind, size: ChipSize = .md, count: String? = nil,
        week: Int? = nil, rotation: Angle = .zero, selected: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.label = label
        self.kind = kind
        self.size = size
        self.count = count
        self.week = week
        self.rotation = rotation
        self.selected = selected
        self.action = action
    }

    /// The dot is decorative but carries the valence, so it grows with the
    /// glyph inside it. Uncapped against the glyph's 1.6x ceiling, which keeps
    /// the circle ahead of its contents rather than behind them.
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 13

    public var body: some View {
        let content = HStack(spacing: 6) {
            ZStack {
                Circle().fill(kind.dot).frame(width: dotSize, height: dotSize)
                Text(kind.glyph)
                    .font(Typography.control(9, weight: .heavy))
                    .foregroundStyle(.white)
            }
            Text(label)
                .font(Typography.control(size.font))
            if let week {
                Text("w\(week)").font(Typography.mono(10))
                    .foregroundStyle(Tokens.Ink.soft)
            }
            if let count {
                Text(count).font(Typography.mono(10, bold: true))
                    .foregroundStyle(Tokens.Ink.soft)
            }
        }
        .padding(.vertical, size.vertical)
        .padding(.horizontal, Tokens.Space.s3)
        .background(selected ? kind.fill : Tokens.Ground.card)
        .foregroundStyle(Tokens.Ink.primary)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(
            selected ? Tokens.Ink.primary : Tokens.Ground.line,
            lineWidth: Tokens.Border.thin
        ))
        .background(
            Capsule().fill(selected ? Tokens.Ink.primary : .clear)
                .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
        )
        .rotationEffect(rotation)
        .accessibilityLabel("\(accessibilityKind): \(label)\(week.map { ", week \($0)" } ?? "")")

        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private var accessibilityKind: String {
        switch kind {
        case .like: "worked"
        case .dislike: "didn't work"
        case .attribute: "attribute"
        }
    }
}

/// Wrapping row of chips, 8–10px gap.
public struct ChipGroup: View {
    let chips: [Chip]

    public init(_ chips: [Chip]) {
        self.chips = chips
    }

    public var body: some View {
        FlowLayout(spacing: 9) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in chip }
        }
    }
}

/// Minimal flow layout for wrapping chip rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for (index, origin) in arrange(proposal: proposal, subviews: subviews).origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(cursor)
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, cursor.x - spacing)
        }
        return (CGSize(width: totalWidth, height: cursor.y + rowHeight), origins)
    }
}
