import Testing
@testable import DesignSystem

// The whole point of this control over `Segmented` is that it has a third
// state you can get back to. `Segmented` always has exactly one option
// selected — right for a status, wrong for a question you may not have
// answered — so these pin the rule that makes the difference.

@Test func answeringAQuestionSelectsThatAnswer() {
    #expect(YesNoControl.picked(true, from: nil) == true)
    #expect(YesNoControl.picked(false, from: nil) == false)
}

@Test func tappingTheChosenAnswerReturnsToUnanswered() {
    // Not "the other answer" — unanswered. Clearing and disagreeing are
    // different acts, and only one of them is a tap on what you already said.
    #expect(YesNoControl.picked(true, from: true) == nil)
    #expect(YesNoControl.picked(false, from: false) == nil)
}

@Test func changingYourMindSwapsRatherThanClears() {
    #expect(YesNoControl.picked(false, from: true) == false)
    #expect(YesNoControl.picked(true, from: false) == true)
}

@Test func theRuleIsATotalFunctionOverEveryState() {
    // Six inputs, all defined: nothing here can land on an unhandled case,
    // which is what lets the view stay a pure rendering of the binding.
    let states: [Bool?] = [nil, true, false]
    for state in states {
        for answer in [true, false] {
            let result = YesNoControl.picked(answer, from: state)
            #expect(result == nil || result == answer, "a pick yields its answer or clears")
        }
    }
}
