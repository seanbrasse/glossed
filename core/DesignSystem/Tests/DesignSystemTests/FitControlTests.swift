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

@Test func aShadeCanMissOnBothAxes() {
    // The point of the change: lightness and undertone are independent.
    var sel = FitControl.picked(.tooLight, from: [])
    sel = FitControl.picked(.tooPink, from: sel)
    #expect(sel == [.tooLight, .tooPink])
}

@Test func anAxisHoldsOneAnswer() {
    // "too light" then "too dark" is a correction, not an accumulation.
    let sel = FitControl.picked(.tooDark, from: [.tooLight, .tooPink])
    #expect(sel == [.tooDark, .tooPink])
}

@Test func justRightStandsAlone() {
    #expect(FitControl.picked(.justRight, from: [.tooLight, .tooPink]) == [.justRight])
    // ...and a miss picked after it clears it.
    #expect(FitControl.picked(.tooPink, from: [.justRight]) == [.tooPink])
}

@Test func tappingASelectedAnswerClearsIt() {
    #expect(FitControl.picked(.tooLight, from: [.tooLight, .tooPink]) == [.tooPink])
    #expect(FitControl.picked(.justRight, from: [.justRight]).isEmpty)
}

@Test func everyAnswerKnowsItsAxis() {
    // Mirrors the database's fit_axis(); the pgTAP suite pins that side.
    #expect(FitAnswer.tooLight.axis == .depth)
    #expect(FitAnswer.tooDark.axis == .depth)
    #expect(FitAnswer.tooPink.axis == .undertone)
    #expect(FitAnswer.tooYellow.axis == .undertone)
    #expect(FitAnswer.tooOrange.axis == .undertone)
    #expect(FitAnswer.justRight.axis == .justRight)
}

@Test func gapCardCapturesAReasonNotJustARejection() {
    // "No" teaches us nothing; the reason routes to a log prompt, a suppressed
    // category, or a price-band signal.
    #expect(GapCard.DismissReason.allCases.count == 4)
    #expect(GapCard.DismissReason.allCases.allSatisfy { $0.label == $0.label.lowercased() })
}
