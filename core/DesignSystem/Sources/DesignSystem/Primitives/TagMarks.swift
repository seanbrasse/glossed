import SwiftUI

// The viewer's two marks (GLO-266): the tag toggle on a photo's bottom-left,
// and the eye beside a listed product that reveals its dot. Both in the kit's
// stroked icon language — 24-grid, round caps, no glyph fonts — because SF
// Symbols carry a different weight and rhythm (KitIcons' whole reason).
//
// `eye` is `ICONS.eye`, read off `screens.jsx` verbatim. **The kit has no tag
// glyph** — checked against `G.ICONS`' key list, not assumed — so `TagIcon`
// is Lucide's `tag`, which is the icon family every glyph in `G.ICONS`
// already comes from. Flagged for the kit pass: `ICONS.tag` should be added
// to the kit with these numbers, so the port direction stays kit → app.

/// A label tag, point down-right, with the pinhole. Lucide `tag` on the kit's
/// 24-grid; the hole is drawn as a tiny stroked circle rather than a filled
/// dot so the mark stays one stroke language at every size.
public struct TagIcon: View {
    private let size: CGFloat

    public init(size: CGFloat = 21) {
        self.size = size
    }

    public var body: some View {
        TagShape()
            .stroke(style: KitIcon.strokeStyle(for: size))
            .frame(width: size, height: size)
    }

    private struct TagShape: Shape {
        func path(in rect: CGRect) -> Path {
            let grid = KitGrid24(rect: rect)
            var path = Path()
            // The label: a rounded square anchored top-left, its far corner
            // pulled to the point at (20.6, 13.5)-ish — Lucide's numbers.
            path.move(to: grid.point(12.6, 2.6))
            path.addQuadCurve(to: grid.point(11.2, 2), control: grid.point(12, 2))
            path.addLine(to: grid.point(4, 2))
            path.addQuadCurve(to: grid.point(2, 4), control: grid.point(2.6, 2.6))
            path.addLine(to: grid.point(2, 11.2))
            path.addQuadCurve(to: grid.point(2.6, 12.6), control: grid.point(2, 12))
            path.addLine(to: grid.point(11.3, 21.3))
            path.addQuadCurve(to: grid.point(14.7, 21.3), control: grid.point(13, 22.3))
            path.addLine(to: grid.point(21.3, 14.7))
            path.addQuadCurve(to: grid.point(21.3, 11.3), control: grid.point(22.3, 13))
            path.closeSubpath()
            // The pinhole.
            path.addEllipse(in: CGRect(
                x: grid.point(6.7, 6.7).x, y: grid.point(6.7, 6.7).y,
                width: grid.scale * 1.6, height: grid.scale * 1.6
            ))
            return path
        }
    }
}

/// `ICONS.eye` — `<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/>`
/// `<circle cx="12" cy="12" r="3"/>`, read off the kit.
public struct EyeIcon: View {
    private let size: CGFloat

    public init(size: CGFloat = 15) {
        self.size = size
    }

    public var body: some View {
        EyeShape()
            .stroke(style: KitIcon.strokeStyle(for: size))
            .frame(width: size, height: size)
    }

    private struct EyeShape: Shape {
        func path(in rect: CGRect) -> Path {
            let grid = KitGrid24(rect: rect)
            var path = Path()
            // The lid: two mirrored arcs meeting at the corners of the eye.
            path.move(to: grid.point(2, 12))
            path.addCurve(to: grid.point(12, 5), control1: grid.point(5.5, 5), control2: grid.point(8, 5))
            path.addCurve(to: grid.point(22, 12), control1: grid.point(16, 5), control2: grid.point(18.5, 5))
            path.addCurve(to: grid.point(12, 19), control1: grid.point(18.5, 19), control2: grid.point(16, 19))
            path.addCurve(to: grid.point(2, 12), control1: grid.point(8, 19), control2: grid.point(5.5, 19))
            path.closeSubpath()
            // The iris.
            path.addEllipse(in: CGRect(
                x: grid.point(9, 9).x, y: grid.point(9, 9).y,
                width: grid.scale * 6, height: grid.scale * 6
            ))
            return path
        }
    }
}

/// The kit's grid helper, package-visible: `KitIcons.swift` keeps a private
/// copy of the same three lines. One of the two retires whenever these files
/// merge; duplicating three lines beats widening that file's API today.
struct KitGrid24 {
    let rect: CGRect

    var scale: CGFloat {
        rect.width / 24
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
    }
}
