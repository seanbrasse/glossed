import Testing
@testable import DesignSystem

@Test func sixFitAnswersInKitOrder() {
    // The order is the design: match first, then the four directions a miss can
    // go. A seventh answer or a reordering is a spec change, not a tweak.
    #expect(FitAnswer.allCases.map(\.rawValue) == [
        "justRight", "tooLight", "tooDark", "tooPink", "tooYellow", "tooOrange"
    ])
}

@Test func onlyJustRightCountsAsAMatch() {
    // A miss still bounds where someone's skin sits — it is signal, not failure.
    #expect(FitAnswer.justRight.isMatch)
    #expect(FitAnswer.allCases.filter(\.isMatch).count == 1)
}

@Test func fitLabelsAreLowercase() {
    #expect(FitAnswer.allCases.allSatisfy { $0.label == $0.label.lowercased() })
}

@Test func gapCardCapturesAReasonNotJustARejection() {
    // "No" teaches us nothing; the reason routes to a log prompt, a suppressed
    // category, or a price-band signal.
    #expect(GapCard.DismissReason.allCases.count == 4)
    #expect(GapCard.DismissReason.allCases.allSatisfy { $0.label == $0.label.lowercased() })
}
