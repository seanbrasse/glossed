import SwiftUI

/// `ICONS.pencil`, and the badge `G.Profile` wraps it in.
///
/// GLO-64's third slice, read straight off `G.ICONS` this session:
/// `<path d="M17 3a2.85 2.85 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5z"/><path d="m15 5 4 4"/>`
///
/// Its own file rather than an addition to `KitIcons.swift`, which sits 43
/// lines under SwiftLint's 300-line ceiling — the same reason `RoutinesModels`
/// left `RoutinesRepository`.
public struct PencilIcon: View {
    private let size: CGFloat

    public init(size: CGFloat = 21) {
        self.size = size
    }

    public var body: some View {
        PencilShape()
            .stroke(style: KitIcon.strokeStyle(for: size))
            .frame(width: size, height: size)
    }

    private struct PencilShape: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = rect.width / 24
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
            }
            var path = Path()
            path.move(to: point(17, 3))
            // The kit's `a2.85 2.85 0 1 1 4 4`. The chord (17,3)→(21,7) is
            // 5.657 long against a 5.7 diameter, so the arc is a half circle
            // about the chord's midpoint to within a twentieth of a point at
            // 24pt. SVG's sweep flag 1 means increasing angle, and in a y-down
            // space that is SwiftUI's `clockwise: false`.
            path.addArc(
                center: point(19, 5),
                radius: 2 * (2 as CGFloat).squareRoot() * scale,
                startAngle: .degrees(225), endAngle: .degrees(405), clockwise: false
            )
            path.addLine(to: point(7.5, 20.5))
            path.addLine(to: point(2, 22))
            path.addLine(to: point(3.5, 16.5))
            path.closeSubpath()
            // The ferrule — the short stroke across the pencil's neck.
            path.move(to: point(15, 5))
            path.addLine(to: point(19, 9))
            return path
        }
    }
}

/// The frame's edit affordance: a 26pt ink-bordered disc on the card's
/// top-right corner, carrying the pencil at the kit's `size={13}`.
///
/// A sticker rather than a control — it is `<span>` in the kit, and the whole
/// card is the tap target. Rendering it as a button would give a card two
/// overlapping ones that do the same thing.
public struct EditBadge: View {
    public init() {}

    public var body: some View {
        PencilIcon(size: 13)
            .foregroundStyle(Tokens.Ink.primary)
            .frame(width: 26, height: 26)
            .background(Tokens.Ground.card)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
            .background(
                Circle().fill(Tokens.Ink.primary)
                    .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
            )
            .accessibilityHidden(true)
    }
}
