import DesignSystem
import SwiftUI

/// A look's media, swipeable (GLO-235). Built to the kit's `G.Feed` frame,
/// which draws this as a **stacked deck** — cards fanned right and rotated,
/// the top one tilting live under your thumb — not a filmstrip and not a
/// page-dots pager. `tech/03` §2 calls that frame stale, and it is, about
/// shade-twin surfacing specifically (delta 1 killed twin cards); the
/// carousel it draws is current and is followed here. What is NOT taken from
/// the frame: its `follow` button and its `tone twin · fenty 240` line, both
/// dead by the same delta.
///
/// A look post is attributed content, never a claim (GLO-196). There is no n
/// on this, no `EvidenceLine`, and the only count is the kit's own
/// `added N photos` — this post's photos, which is chrome and reads as chrome.
public struct LookMediaPager: View {
    @State private var deck: LookMediaDeck
    /// Live drag offset of the top card. Zero except mid-drag.
    @State private var dx: CGFloat = 0
    @State private var dragging = false

    public init(_ media: [LookMedia]) {
        _deck = State(initialValue: LookMediaDeck(media))
    }

    public var body: some View {
        if deck.isEmpty {
            // A look with no media is not a look. Nothing to draw, and an
            // empty frame reserving height would be a lie about the content.
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                if let line = deck.chromeLine {
                    Text(line)
                        .font(Typography.mono(11))
                        .foregroundStyle(Tokens.Ink.soft)
                }
                stack
            }
        }
    }

    private var stack: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(deck.items.enumerated()), id: \.element.id) { index, item in
                card(item, depth: deck.depth(of: index))
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: LookDeckGeometry.cardHeight,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .gesture(swipe)
    }

    private func card(_ item: LookMedia, depth: Int) -> some View {
        let isTop = depth == 0
        let fan = Double(depth) * LookDeckGeometry.depthRotation
        let tilt = isTop && dragging ? Double(dx) / LookDeckGeometry.dragTiltDivisor : 0
        return LookMediaPage(media: item)
            .frame(width: LookDeckGeometry.cardWidth, height: LookDeckGeometry.cardHeight)
            // Rotate then translate, and about the bottom-left corner — the
            // frame's `transformOrigin: 'bottom left'`, which is what makes
            // the fan open rightward instead of pivoting around the middle.
            .rotationEffect(.degrees(fan + tilt), anchor: .bottomLeading)
            .offset(x: CGFloat(depth) * LookDeckGeometry.depthOffset + (isTop ? dx : 0))
            .opacity(depth > LookDeckGeometry.visibleDepth ? 0 : 1)
            .zIndex(Double(deck.count - depth))
            // Only the top card takes the touch, so a drag never grabs a
            // card buried under it.
            .allowsHitTesting(isTop)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag in
                // Unanimated on purpose: the kit sets `transition: none`
                // while dragging, so the card tracks the thumb exactly.
                dragging = true
                dx = drag.translation.width
            }
            .onEnded { drag in
                dragging = false
                withAnimation(Tokens.Motion.pop(LookDeckGeometry.settleDuration)) {
                    deck.apply(LookMediaDeck.step(forDragWidth: drag.translation.width))
                    dx = 0
                }
            }
    }
}

/// ONE item, drawn. This is the seam: a second media kind is a case here and
/// a change nowhere else — the deck's ordering, paging and chrome all work in
/// terms of `LookMedia`, never in terms of photos.
struct LookMediaPage: View {
    let media: LookMedia

    var body: some View {
        content
            .frame(width: LookDeckGeometry.cardWidth, height: LookDeckGeometry.cardHeight)
            .background(Tokens.Ground.card)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
            )
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .fill(Tokens.Ink.primary)
                    .offset(x: Tokens.Shadow.md, y: Tokens.Shadow.md)
            )
    }

    @ViewBuilder private var content: some View {
        switch media.kind {
        case let .photo(source):
            photo(source)
        }
    }

    @ViewBuilder private func photo(_ source: LookMediaSource) -> some View {
        switch source {
        case let .data(bytes):
            local(bytes)
        case let .remote(url):
            // Never a broken image (delta 14): a failed or pending load holds
            // the card's ground rather than showing a torn-page glyph.
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Tokens.Support.lilacSoft
            }
        }
    }

    @ViewBuilder private func local(_ bytes: Data) -> some View {
        #if canImport(UIKit)
            if let image = UIImage(data: bytes) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Tokens.Support.lilacSoft
            }
        #else
            // macOS test builds never render this; the card ground stands in
            // so the package still compiles there.
            Tokens.Support.lilacSoft
        #endif
    }
}
