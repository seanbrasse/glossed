import SwiftUI

/// The stylist's mark (08 §4): a speech bubble with a small spark in it —
/// the discover spark, spoken. Same 24-grid, same stroke, so it sits between
/// the spark and the shelf in the nav without reading as a different voice.
public struct StylistIcon: View {
    private let size: CGFloat

    public init(size: CGFloat = 21) {
        self.size = size
    }

    public var body: some View {
        StylistShape()
            .stroke(style: KitIcon.strokeStyle(for: size))
            .frame(width: size, height: size)
    }

    private struct StylistShape: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = rect.width / 24
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
            }
            var path = Path()
            // The bubble: a rounded rect with its tail at the bottom left.
            path.move(to: point(8, 18.5))
            path.addLine(to: point(5, 21))
            path.addLine(to: point(5, 18.5))
            path.addQuadCurve(to: point(3, 16.5), control: point(3, 18.5))
            path.addLine(to: point(3, 6))
            path.addQuadCurve(to: point(5.5, 3.5), control: point(3, 3.5))
            path.addLine(to: point(18.5, 3.5))
            path.addQuadCurve(to: point(21, 6), control: point(21, 3.5))
            path.addLine(to: point(21, 16))
            path.addQuadCurve(to: point(18.5, 18.5), control: point(21, 18.5))
            path.closeSubpath()
            // The spark inside, four points, small.
            path.move(to: point(12, 7))
            path.addLine(to: point(13, 10))
            path.addLine(to: point(16, 11))
            path.addLine(to: point(13, 12))
            path.addLine(to: point(12, 15))
            path.addLine(to: point(11, 12))
            path.addLine(to: point(8, 11))
            path.addLine(to: point(11, 10))
            path.closeSubpath()
            return path
        }
    }
}
