import SwiftUI

/// The kit's stroked icon language (GLO-64's first slice — the nav's
/// glyphs, hand-ported from the kit's 24-grid SVG paths). Same voice as
/// `ProductMock`: drawn strokes, round caps, no glyph fonts — SF Symbols
/// carry a different weight and rhythm, which is why the shipped nav never
/// quite looked like the frames.
///
/// Every shape draws on the kit's 24×24 grid and scales to its frame; the
/// stroke scales with it so a 21pt icon strokes at the kit's ~2pt.
public enum KitIcon {
    /// Kit strokeWidth 2.25 on the 24 grid.
    static func strokeStyle(for size: CGFloat, width: CGFloat = 2.25) -> StrokeStyle {
        StrokeStyle(lineWidth: width * size / 24, lineCap: .round, lineJoin: .round)
    }
}

/// The four-point spark, its inner corners filleted the way the kit's
/// arcs round them.
public struct SparklesIcon: View {
    private let size: CGFloat

    public init(size: CGFloat = 21) {
        self.size = size
    }

    public var body: some View {
        SparkShape()
            .stroke(style: KitIcon.strokeStyle(for: size))
            .frame(width: size, height: size)
    }

    private struct SparkShape: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = rect.width / 24
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
            }
            var path = Path()
            path.move(to: point(12, 3))
            path.addLine(to: point(13.9, 8.8))
            path.addQuadCurve(to: point(15.2, 10.1), control: point(14.22, 9.78))
            path.addLine(to: point(21, 12))
            path.addLine(to: point(15.2, 13.9))
            path.addQuadCurve(to: point(13.9, 15.2), control: point(14.22, 14.22))
            path.addLine(to: point(12, 21))
            path.addLine(to: point(10.1, 15.2))
            path.addQuadCurve(to: point(8.8, 13.9), control: point(9.78, 14.22))
            path.addLine(to: point(3, 12))
            path.addLine(to: point(8.8, 10.1))
            path.addQuadCurve(to: point(10.1, 8.8), control: point(9.78, 9.78))
            path.closeSubpath()
            return path
        }
    }
}

/// Two bays and a bottle-neck — the kit's shelf mark.
public struct ShelfIcon: View {
    private let size: CGFloat

    public init(size: CGFloat = 21) {
        self.size = size
    }

    public var body: some View {
        ShelfShape()
            .stroke(style: KitIcon.strokeStyle(for: size))
            .frame(width: size, height: size)
    }

    private struct ShelfShape: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = rect.width / 24
            func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
                CGRect(
                    x: rect.minX + x * scale, y: rect.minY + y * scale,
                    width: width * scale, height: height * scale
                )
            }
            var path = Path()
            path.addRoundedRect(in: box(2.5, 9, 8, 12), cornerSize: CGSize(width: 2.2 * scale, height: 2.2 * scale))
            path.move(to: CGPoint(x: rect.minX + 6.5 * scale, y: rect.minY + 9 * scale))
            path.addLine(to: CGPoint(x: rect.minX + 6.5 * scale, y: rect.minY + 5 * scale))
            path.addLine(to: CGPoint(x: rect.minX + 9.5 * scale, y: rect.minY + 5 * scale))
            path.addRoundedRect(in: box(15, 13, 7.5, 8), cornerSize: CGSize(width: 2.2 * scale, height: 2.2 * scale))
            return path
        }
    }
}

/// The plus, drawn — two strokes at the kit's 2.75 weight, not a glyph.
public struct PlusIcon: View {
    private let size: CGFloat

    public init(size: CGFloat = 24) {
        self.size = size
    }

    public var body: some View {
        PlusShape()
            .stroke(style: KitIcon.strokeStyle(for: size, width: 2.75))
            .frame(width: size, height: size)
    }

    private struct PlusShape: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = rect.width / 24
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 5 * scale, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + 19 * scale, y: rect.midY))
            path.move(to: CGPoint(x: rect.midX, y: rect.minY + 5 * scale))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + 19 * scale))
            return path
        }
    }
}
