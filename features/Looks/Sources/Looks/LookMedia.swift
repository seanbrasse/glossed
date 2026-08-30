import CoreGraphics
import Foundation

/// One piece of a look's media, and where it sits in the look (GLO-235).
///
/// `kind` is the seam. A second media kind changes `LookMediaPage` — the
/// view that draws ONE item — and nothing else: not the deck's ordering, not
/// its paging, not its chrome. (GLO-234 was the expected second kind; Sean
/// pulled it back to maybe-V2 after seeing the moderation cost, so nothing is
/// arriving behind this soon. The seam costs one `switch` and is kept.)
public struct LookMedia: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case photo(LookMediaSource)
    }

    public let id: UUID
    /// `look_photos.position` (0043) — dense from zero, unique per look, and
    /// maintained by the composer (GLO-232). The deck sorts by it rather than
    /// trusting the order rows arrived in.
    public let position: Int
    public let kind: Kind

    public init(id: UUID = UUID(), position: Int, kind: Kind) {
        self.id = id
        self.position = position
        self.kind = kind
    }
}

/// Where an item's bytes come from. A composed draft has them in hand; a
/// saved look has an `r2_key` someone resolved to a URL.
public enum LookMediaSource: Sendable, Equatable {
    case data(Data)
    case remote(URL)
}

/// The kit's numbers, in one place and citable. All of these are read off
/// `G.Feed` in the design kit (`ui_kits/glossed-app/screens.jsx`), which draws
/// this carousel as a **stacked deck** rather than a filmstrip.
public enum LookDeckGeometry {
    /// Card size. The kit's `Photo h={196}` inside a `width:110` wrapper.
    public static let cardWidth: CGFloat = 110
    public static let cardHeight: CGFloat = 196
    /// `translateX(d*18)` — each card further down the deck slides right.
    public static let depthOffset: CGFloat = 18
    /// `rotate(d*3.5deg)` — and the fan.
    public static let depthRotation: Double = 3.5
    /// The top card tilts live with the drag at `dx/50` degrees.
    public static let dragTiltDivisor: Double = 50
    /// Cards more than one deep are drawn but invisible (`opacity: d>1 ? 0 : 1`).
    public static let visibleDepth = 1
    /// `dx < -55` advances, `dx > 55` goes back.
    public static let swipeThreshold: CGFloat = 55
    /// `transform 320ms cubic-bezier(.2,.9,.3,1.3)` — the curve is already a
    /// token (`Tokens.Motion.pop`), so only the duration lives here.
    public static let settleDuration: Double = 0.32
}

/// The deck's state: what is in it, in what order, and which card is on top.
///
/// Pure and `Equatable` so the paging rules are testable without a view —
/// the 55pt threshold and the cyclic depth formula are the kit's decisions
/// and deserve assertions rather than a gesture closure nobody can run.
public struct LookMediaDeck: Sendable, Equatable {
    /// Ordered by `position`, ties broken by id so two loads read the same.
    public let items: [LookMedia]
    public private(set) var slide: Int

    public init(_ unordered: [LookMedia]) {
        items = unordered.sorted { ($0.position, $0.id.uuidString) < ($1.position, $1.id.uuidString) }
        slide = 0
    }

    public var count: Int {
        items.count
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    /// Chrome appears only above one item. A single-photo look renders as it
    /// always has: no count line, no fan, nothing to swipe. (The kit
    /// hardcodes three shots so it never met this case — and its own string
    /// would have read "added 1 photos".)
    public var showsChrome: Bool {
        count > 1
    }

    /// The kit's line, above the stack: `'added ' + shots.length + ' photos'`.
    ///
    /// It counts THIS post's own photos and nothing else. A look post is
    /// attributed content, never a claim (GLO-196), so there is no n here, no
    /// cohort, and nothing that could be read as a sample size — this is the
    /// page indicator, and it reads as one.
    public var chromeLine: String? {
        showsChrome ? "added \(count) photos" : nil
    }

    /// How many places from the top a card sits — the kit's
    /// `(i - slide + n) % n`. The deck is cyclic: past the last card you
    /// arrive back at the first.
    public func depth(of index: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index - slide + count) % count
    }

    public mutating func advance() {
        guard count > 0 else { return }
        slide = (slide + 1) % count
    }

    public mutating func goBack() {
        guard count > 0 else { return }
        slide = (slide + count - 1) % count
    }

    /// What a finished drag of `width` points does. The kit's thresholds
    /// exactly: past 55 in either direction, and nothing at all inside it.
    public enum Step: Sendable, Equatable {
        case forward
        case back
        case stay
    }

    public static func step(forDragWidth width: CGFloat) -> Step {
        if width < -LookDeckGeometry.swipeThreshold {
            return .forward
        }
        if width > LookDeckGeometry.swipeThreshold {
            return .back
        }
        return .stay
    }

    public mutating func apply(_ step: Step) {
        switch step {
        case .forward: advance()
        case .back: goBack()
        case .stay: break
        }
    }
}
