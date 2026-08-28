import DataKit
import Foundation
import Observation

/// Where a list came from. Three sources, one screen — the kit does not branch
/// after the pick, because a list is a list once it is text.
public enum ImportSource: String, CaseIterable, Sendable {
    case notes, csv, screenshot

    /// The kit's own labels.
    public var title: String {
        switch self {
        case .notes: "paste from notes"
        case .csv: "upload a csv"
        case .screenshot: "screenshot of a haul"
        }
    }

    public var subtitle: String {
        switch self {
        case .notes: "the list you already keep"
        case .csv: "one product per line"
        case .screenshot: "we read the text, you confirm"
        }
    }
}

/// What became of one line.
///
/// Three cases, and the third is not a failure. *"The ladder never dead-ends"*
/// applies here too: a line we cannot match is handed to the ladder, which is
/// the same promise the ladder's own "none of these" makes.
public enum ImportResolution: Equatable, Sendable {
    /// A variant, exactly. This one can go on the shelf as it stands.
    case matched(variantID: UUID)
    /// A product, but not which size or shade. Someone has to pick
    /// (`tech/01` §16's middle case, still unowned — GLO-56).
    case needsSize(productID: UUID)
    /// Nothing in the catalog. Goes to the ladder rather than being dropped.
    case noMatch
}

public struct ImportLine: Identifiable, Sendable, Equatable {
    /// Position in the pasted list, which is the only stable identity a line
    /// has — two lines of a shopping list are routinely identical.
    public let id: Int
    public let text: String
    public let resolution: ImportResolution

    public init(id: Int, text: String, resolution: ImportResolution) {
        self.id = id
        self.text = text
        self.resolution = resolution
    }
}

/// What the import screen needs from the parser, and nothing more.
///
/// The parse itself is a server call — an LLM reading each line against the
/// catalog — and PRD §16 makes its rule non-negotiable: *"AI lookup may only
/// fill fields it can attribute to a real source. Empty beats fabricated."*
/// This protocol is where that boundary sits; nothing on this side can invent
/// a match, because the only thing it is given is a verdict per line.
public protocol ImportParsing: Sendable {
    /// One resolution per line, in the order the lines were given.
    func parse(_ lines: [String]) async throws(GlossedError) -> [ImportResolution]
}

@MainActor
@Observable
public final class ImportModel {
    /// Nil until someone picks; the kit shows the three source cards until then.
    public var source: ImportSource?
    public var text: String
    public private(set) var lines: [ImportLine] = []
    public private(set) var isParsing = false
    public private(set) var failure: GlossedError?

    private let parser: any ImportParsing

    public init(parser: any ImportParsing, text: String = "") {
        self.parser = parser
        self.text = text
    }

    /// The lines as typed, blanks dropped.
    ///
    /// A trailing newline is what every paste has and is not a product. Kept
    /// separate from `lines` because the count has to be right *before* anything
    /// is parsed — "we read 5 lines" is a statement about the paste, not about
    /// the catalog.
    public var rawLines: [String] {
        ImportModel.rawLines(from: text)
    }

    /// `nonisolated` because splitting a string is arithmetic and belongs to no
    /// actor — and because the rule is worth testing without a `@MainActor`
    /// test. Same reasoning as `ShelfModel.ordered`.
    public nonisolated static func rawLines(from text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Matched to an exact variant — the number the kit puts next to "matched
    /// outright". Deliberately **not** the number that can be added: a line
    /// still needing a size is not a match, and counting it as one would
    /// overstate what the parse achieved.
    public var matchedOutrightCount: Int {
        lines.count {
            if case .matched = $0.resolution {
                true
            } else {
                false
            }
        }
    }

    /// Everything that can reach the shelf from this screen — matched, plus the
    /// ones only waiting on a size. The kit's button says "add 4 to your shelf"
    /// for a list of five where three matched outright and one needs a size.
    public var addableCount: Int {
        lines.count { $0.resolution != .noMatch }
    }

    /// The lines the ladder will have to take.
    public var ladderCount: Int {
        lines.count { $0.resolution == .noMatch }
    }

    public func parse() async {
        let toParse = rawLines
        guard !toParse.isEmpty else {
            lines = []
            return
        }
        isParsing = true
        defer { isParsing = false }
        do {
            let resolutions = try await parser.parse(toParse)
            // A parser that returns a different number of verdicts than it was
            // given has lost track of which line is which, and zipping the two
            // would silently attach one line's result to another's text — a
            // wrong match presented as a confident one. Refuse instead.
            guard resolutions.count == toParse.count else {
                lines = []
                failure = ImportModel.miscountedError
                return
            }
            lines = zip(toParse.indices, zip(toParse, resolutions)).map { index, pair in
                ImportLine(id: index, text: pair.0, resolution: pair.1)
            }
            failure = nil
        } catch {
            // Cleared only once an answer arrives, and the lines go with it: a
            // stale list under a fresh error would read as a parse that
            // half-worked.
            lines = []
            failure = error
        }
    }

    static let miscountedError = GlossedError(
        .unknown,
        userMessage: "couldn't read that list — try pasting it again",
        debugDetail: "parser returned a different number of resolutions than lines"
    )
}
