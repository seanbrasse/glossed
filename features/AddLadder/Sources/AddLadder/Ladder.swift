import Foundation

/// The five rungs of the submission ladder, in the order they are offered
/// (tech/01 §6, domain.md §3.1). The ordering is the type: a rung knows what
/// comes after it, so "none of these" cannot be wired to a dead end.
public enum Rung: Int, CaseIterable, Comparable, Sendable {
    case search = 1
    case barcode
    case nearMatches
    case create
    case confirm

    public static func < (lhs: Rung, rhs: Rung) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The rungs that show candidates and therefore owe the user a way past
    /// them. `create` asks for input instead, and `confirm` is the end.
    public var offersNoneOfThese: Bool {
        self < .create
    }

    /// Non-nil for every rung that offers "none of these" — the invariant the
    /// screens rest on, stated once here rather than re-derived per view.
    public var next: Rung? {
        Rung(rawValue: rawValue + 1)
    }
}

/// One trip down the ladder: which rung we are on, what the user has told us
/// so far, and how it ended. State, not policy — nothing here decides what a
/// good match is, and nothing here talks to the network.
public struct Ladder: Equatable, Sendable {
    /// How the ladder ended. Both outcomes put something on the shelf; the
    /// difference is whether the catalog already knew about it.
    public enum Resolution: Equatable, Sendable {
        case matched(variantID: UUID)
        case created(productID: UUID)
    }

    public private(set) var rung: Rung
    /// Every rung visited, in order. The rail renders from this, so entering
    /// at the barcode rung does not show a search step nobody was offered.
    public private(set) var trail: [Rung]
    /// What the user typed, carried down every rung so the create rung arrives
    /// pre-filled with the words they already said once.
    public private(set) var query: String
    /// Set when a scan happened — a GTIN that missed is still the strongest
    /// hint the near-match rung will get.
    public private(set) var scannedGTIN: String?
    public private(set) var resolution: Resolution?

    /// Barcode is the pushed path (tech/01 §6), so entering there is ordinary.
    public init(entry: Rung = .search, query: String = "") {
        rung = entry
        trail = [entry]
        self.query = Ladder.tidy(query)
    }

    public var isResolved: Bool {
        resolution != nil
    }

    /// True while there is somewhere left to go. The ladder is a dead end only
    /// once it has actually resolved.
    public var canAdvance: Bool {
        !isResolved && rung.next != nil
    }

    /// "None of these." Always advances — never a dead end, at any rung, and
    /// callers do not get to decide where it goes: the rung order does.
    public mutating func noneOfThese() {
        guard !isResolved, let next = rung.next else { return }
        move(to: next)
    }

    /// Refining does not move the ladder — a query is a question about the
    /// rung you are on.
    public mutating func refine(query: String) {
        guard !isResolved else { return }
        self.query = Ladder.tidy(query)
    }

    /// A scan that found nothing. The GTIN is kept and the ladder advances,
    /// because a miss is still progress.
    public mutating func scanMissed(gtin: String) {
        guard !isResolved, rung == .barcode, let next = rung.next else { return }
        scannedGTIN = gtin
        move(to: next)
    }

    /// A candidate was picked at any rung that offers candidates.
    public mutating func matched(variantID: UUID) {
        guard !isResolved else { return }
        resolution = .matched(variantID: variantID)
    }

    /// The create rung submitted: the product exists in personal scope, and
    /// the ladder lands on the confirmation that says so.
    public mutating func created(productID: UUID) {
        guard !isResolved else { return }
        resolution = .created(productID: productID)
        move(to: .confirm)
    }

    private mutating func move(to next: Rung) {
        rung = next
        trail.append(next)
    }

    /// Whitespace-collapsed but otherwise untouched: the create rung shows this
    /// back to the user, so it stays what they typed rather than a normalized
    /// form only the dedupe pass should ever see.
    static func tidy(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
