import DataKit
import Foundation
import Testing
@testable import Import

/// The kit's own paste, messy on purpose — the last line is deliberately vague
/// and is the case the parser has to survive.
private let kitPaste = """
rare beauty soft pinch — joy
fenty pro filtr 240
rhode peptide lip tint ribbon
ouai detox shampoo
that olaplex one
"""

private actor FakeParser: ImportParsing {
    private let resolutions: [ImportResolution]
    private let failure: GlossedError?
    private let overrideCount: Int?

    init(_ resolutions: [ImportResolution] = [], failure: GlossedError? = nil, returning overrideCount: Int? = nil) {
        self.resolutions = resolutions
        self.failure = failure
        self.overrideCount = overrideCount
    }

    func parse(_ lines: [String]) async throws(GlossedError) -> [ImportResolution] {
        if let failure {
            throw failure
        }
        if let overrideCount {
            return Array(repeating: .noMatch, count: overrideCount)
        }
        return resolutions.isEmpty ? Array(repeating: .noMatch, count: lines.count) : resolutions
    }
}

/// The kit's five-line outcome: three matched, one needing a size, one for the
/// ladder.
private let kitOutcome: [ImportResolution] = [
    .matched(variantID: UUID()),
    .matched(variantID: UUID()),
    .matched(variantID: UUID()),
    .needsSize(productID: UUID()),
    .noMatch
]

@MainActor
private func model(
    _ text: String = kitPaste,
    resolutions: [ImportResolution] = [],
    failure: GlossedError? = nil,
    returning overrideCount: Int? = nil
) -> ImportModel {
    ImportModel(parser: FakeParser(resolutions, failure: failure, returning: overrideCount), text: text)
}

// MARK: - Reading the paste

@Test func blankLinesAreNotProducts() {
    // Every paste ends with a newline, and a list someone actually keeps has
    // gaps in it. "We read 7 lines" for five products is a lie about their list.
    let messy = "rare beauty\n\n  \nfenty 240\n\n"
    #expect(ImportModel.rawLines(from: messy) == ["rare beauty", "fenty 240"])
}

@Test func linesKeepTheirOwnWordsAndTheirOrder() {
    // The line is shown back to the user, so it stays what they typed apart
    // from the whitespace around it.
    #expect(ImportModel.rawLines(from: kitPaste).first == "rare beauty soft pinch — joy")
    #expect(ImportModel.rawLines(from: kitPaste).count == 5)
    #expect(ImportModel.rawLines(from: "  padded  ") == ["padded"])
}

@Test func anEmptyPasteReadsAsNoLinesRatherThanOne() {
    #expect(ImportModel.rawLines(from: "").isEmpty)
    #expect(ImportModel.rawLines(from: "\n\n \n").isEmpty)
}

// MARK: - The two counts, which are different numbers

@MainActor
@Test func matchedOutrightDoesNotCountTheOnesStillNeedingASize() async {
    // The kit shows "3 of 5 matched outright" and a button saying "add 4".
    // Collapsing them would overstate what the parse actually achieved.
    let live = model(resolutions: kitOutcome)
    await live.parse()
    #expect(live.rawLines.count == 5)
    #expect(live.matchedOutrightCount == 3)
    #expect(live.addableCount == 4)
    #expect(live.ladderCount == 1)
}

@MainActor
@Test func aListNothingMatchedStillOffersTheLadderRatherThanFailing() async {
    // Nothing dead-ends. Five unmatched lines is a full ladder handoff, not an
    // error state.
    let live = model()
    await live.parse()
    #expect(live.lines.count == 5)
    #expect(live.addableCount == 0)
    #expect(live.ladderCount == 5)
    #expect(live.failure == nil)
}

// MARK: - What the screen refuses to do

@MainActor
@Test func aParserThatLosesCountIsRefusedRatherThanZipped() async {
    // Zipping four verdicts onto five lines attaches one line's result to
    // another line's text — a wrong match, presented as a confident one. That
    // is worse than showing nothing.
    let live = model(returning: 4)
    await live.parse()
    #expect(live.lines.isEmpty)
    #expect(live.failure?.code == .unknown)
}

@MainActor
@Test func aFailedParseLeavesNoStaleLinesUnderTheError() async {
    // A list from the previous attempt sitting under a fresh error reads as a
    // parse that half-worked.
    let live = model(resolutions: kitOutcome)
    await live.parse()
    #expect(live.lines.count == 5)

    let broken = model(failure: GlossedError(.offline, userMessage: "no connection"))
    broken.text = kitPaste
    await broken.parse()
    #expect(broken.lines.isEmpty)
    #expect(broken.failure != nil)
}

@MainActor
@Test func parsingNothingIsNotAnError() async {
    let live = model("")
    await live.parse()
    #expect(live.lines.isEmpty)
    #expect(live.failure == nil)
}

// MARK: - The source cards

@Test func everySourceTheKitOffersHasItsOwnCopy() {
    #expect(ImportSource.allCases.count == 3)
    #expect(ImportSource.notes.title == "paste from notes")
    #expect(ImportSource.csv.subtitle == "one product per line")
    #expect(ImportSource.screenshot.title == "screenshot of a haul")
    for source in ImportSource.allCases {
        #expect(!source.title.isEmpty)
        #expect(!source.subtitle.isEmpty)
        #expect(source.title == source.title.lowercased())
    }
}
