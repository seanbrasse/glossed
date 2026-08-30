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

/// Renders one of the drawer's four kit glyphs at the kit's own `size={18}`.
///
/// GLO-64's second slice. The first ported the nav's three marks; these are the
/// + drawer's four — `search` · `file` · `folder` · `layers` — read straight
/// off `G.ICONS` this session, and cross-checked by pulling `sparkles` and
/// `shelf` from the same object and finding them identical to what is already
/// drawn above.
struct DrawerGlyphView: View {
    let glyph: ActionDrawer.Glyph
    /// `G.drawerOptions` draws every one of the four at `size={18}`.
    var size: CGFloat = 18

    var body: some View {
        DrawerGlyphShape(glyph: glyph)
            .stroke(style: KitIcon.strokeStyle(for: size))
            .frame(width: size, height: size)
    }
}

/// One `Shape` switching on the glyph rather than four views, because a
/// `@ViewBuilder` switch produces a `View` and `.stroke` is a `Shape` member —
/// the four would each have to carry their own stroke, and then the kit's one
/// stroke weight would live in four places.
private struct DrawerGlyphShape: Shape {
    let glyph: ActionDrawer.Glyph

    func path(in rect: CGRect) -> Path {
        switch glyph {
        case .search: SearchShape().path(in: rect)
        case .file: FileShape().path(in: rect)
        case .folder: FolderShape().path(in: rect)
        case .layers: LayersShape().path(in: rect)
        }
    }
}

/// The kit's grid helper: every path below is written in the kit's own 24×24
/// coordinates and scaled to the frame, so re-syncing against `screens.jsx` is
/// reading the numbers off rather than re-deriving them.
private struct KitGrid {
    let rect: CGRect

    var scale: CGFloat {
        rect.width / 24
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
    }
}

/// `ICONS.search` — `<circle cx=11 cy=11 r=8/><path d="m21 21-4.3-4.3"/>`
private struct SearchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = KitGrid(rect: rect)
        var path = Path()
        path.addEllipse(in: CGRect(
            origin: grid.point(3, 3),
            size: CGSize(width: 16 * grid.scale, height: 16 * grid.scale)
        ))
        path.move(to: grid.point(21, 21))
        path.addLine(to: grid.point(16.7, 16.7))
        return path
    }
}

/// `ICONS.file` — a page with the top-right corner folded. The kit's `z` is
/// what draws the fold's hypotenuse, so closing the subpath is load-bearing
/// here rather than tidiness.
private struct FileShape: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = KitGrid(rect: rect)
        let radius = 2 * grid.scale
        var path = Path()
        path.move(to: grid.point(14, 3))
        path.addArc(tangent1End: grid.point(5, 3), tangent2End: grid.point(5, 21), radius: radius)
        path.addArc(tangent1End: grid.point(5, 21), tangent2End: grid.point(19, 21), radius: radius)
        path.addArc(tangent1End: grid.point(19, 21), tangent2End: grid.point(19, 8), radius: radius)
        path.addLine(to: grid.point(19, 8))
        path.closeSubpath()
        path.move(to: grid.point(14, 3))
        path.addLine(to: grid.point(14, 8))
        path.addLine(to: grid.point(19, 8))
        return path
    }
}

/// `ICONS.folder` — one closed outline whose top edge steps up into the tab.
private struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = KitGrid(rect: rect)
        let radius = 2 * grid.scale
        var path = Path()
        path.move(to: grid.point(20, 20))
        path.addArc(tangent1End: grid.point(22, 20), tangent2End: grid.point(22, 6), radius: radius)
        path.addArc(tangent1End: grid.point(22, 6), tangent2End: grid.point(12.1, 6), radius: radius)
        path.addLine(to: grid.point(12.1, 6))
        // The tab's shoulder: the kit's two small arcs (`a2 2 0 0 1 -1.69-.9`
        // and `A2 2 0 0 0 7.93 3`) with the sharp vertex as the control point —
        // the same approximation SparklesIcon already makes for the kit's
        // filleted corners, and at r=2 on a 24 grid it is under half a point.
        path.addQuadCurve(to: grid.point(10.41, 5.1), control: grid.point(11.4, 5.6))
        path.addLine(to: grid.point(9.6, 3.9))
        path.addQuadCurve(to: grid.point(7.93, 3), control: grid.point(9.1, 3.2))
        path.addLine(to: grid.point(4, 3))
        path.addArc(tangent1End: grid.point(2, 3), tangent2End: grid.point(2, 20), radius: radius)
        path.addArc(tangent1End: grid.point(2, 20), tangent2End: grid.point(20, 20), radius: radius)
        path.closeSubpath()
        return path
    }
}

/// `ICONS.layers` — a rounded rhombus over two sweeps, the stack read
/// edge-on. Three subpaths, exactly as the kit draws them.
private struct LayersShape: Shape {
    func path(in rect: CGRect) -> Path {
        let grid = KitGrid(rect: rect)
        var path = Path()
        path.move(to: grid.point(12.83, 2.18))
        path.addQuadCurve(to: grid.point(11.17, 2.18), control: grid.point(12, 1.75))
        path.addLine(to: grid.point(2.6, 6.08))
        path.addQuadCurve(to: grid.point(2.6, 7.91), control: grid.point(1.85, 7))
        path.addLine(to: grid.point(11.18, 11.82))
        path.addQuadCurve(to: grid.point(12.84, 11.82), control: grid.point(12, 12.25))
        path.addLine(to: grid.point(21.42, 7.92))
        path.addQuadCurve(to: grid.point(21.42, 6.09), control: grid.point(22.15, 7))
        path.closeSubpath()
        for baseline in [12.65, 17.65] as [CGFloat] {
            path.move(to: grid.point(22, baseline))
            path.addLine(to: grid.point(12.83, baseline + 4.16))
            path.addQuadCurve(
                to: grid.point(11.17, baseline + 4.16),
                control: grid.point(12, baseline + 4.6)
            )
            path.addLine(to: grid.point(2, baseline))
        }
        return path
    }
}
