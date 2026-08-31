import SwiftUI

/// The save mark — a bookmark, drawn (the TagIcon/PencilIcon rule: kit marks
/// are shapes, never SF Symbols). Sean's Aug 31 batch 2: the default
/// want-to-try collection wears "a save icon on it."
///
/// The classic bookmark path in the kit's 24-unit space:
/// `M19 21l-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z` — a lucide-family
/// outline, matching the stroke weight the other marks carry.
public struct SaveIcon: View {
    private let size: CGFloat

    public init(size: CGFloat = 21) {
        self.size = size
    }

    public var body: some View {
        SaveShape()
            .stroke(style: KitIcon.strokeStyle(for: size))
            .frame(width: size, height: size)
    }

    private struct SaveShape: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = rect.width / 24
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
            }
            var path = Path()
            path.move(to: point(19, 21))
            path.addLine(to: point(12, 17))
            path.addLine(to: point(5, 21))
            path.addLine(to: point(5, 5))
            // `a2 2 0 0 1 2-2` — the top corners round with 2-unit arcs; the
            // SVG's sweep 1 in a y-down space is SwiftUI's clockwise: false.
            path.addArc(
                center: point(7, 5), radius: 2 * scale,
                startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
            )
            path.addLine(to: point(17, 3))
            path.addArc(
                center: point(17, 5), radius: 2 * scale,
                startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false
            )
            path.closeSubpath()
            return path
        }
    }
}
