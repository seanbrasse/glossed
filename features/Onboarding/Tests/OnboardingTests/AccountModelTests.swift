import DataKit
import Foundation
import Testing
@testable import Onboarding

// The account walk and the birthday gate, with fixtures on both sides of
// every rule (the session-12 discipline). `today` is injected so age is a
// fact, not a race.

private let calendar = Calendar(identifier: .gregorian)

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
}

/// A fixed "today" for every age fact below: 29 August 2026.
private let fixedToday = date(2026, 8, 29)

@MainActor
@Test func theAppleWalkSkipsThePhonePair() {
    let model = AccountModel(today: fixedToday)
    #expect(model.stage == .method)
    model.chooseApple()
    #expect(model.stage == .birthday) // the one thing apple cannot supply
}

@MainActor
@Test func thePhoneWalkIsMethodPhoneCodeBirthday() {
    let model = AccountModel(today: fixedToday)
    model.choosePhone()
    #expect(model.stage == .phone)
    model.phoneNumber = "+1 555 0134"
    model.sendCode()
    #expect(model.stage == .code)
    model.enterCode("482913")
    model.verifyCode()
    #expect(model.stage == .birthday)
}

@MainActor
@Test func everyScreenBacksUpOneAndTheMapMatchesTheMethod() {
    let phone = AccountModel(today: fixedToday)
    phone.choosePhone()
    phone.phoneNumber = "5550134"
    phone.sendCode()
    phone.enterCode("482913")
    phone.verifyCode()
    #expect(phone.back()) // birthday → code, because phone got us here
    #expect(phone.stage == .code)
    #expect(phone.back())
    #expect(phone.stage == .phone)
    #expect(phone.back())
    #expect(phone.stage == .method)
    #expect(!phone.back()) // method-back leaves the flow — the caller owns it

    let apple = AccountModel(today: fixedToday)
    apple.chooseApple()
    #expect(apple.back()) // birthday → method, no phone pair to return to
    #expect(apple.stage == .method)
}

@MainActor
@Test func theCodeGateWantsSevenPhoneDigitsAndExactlySixCodeDigits() {
    let model = AccountModel(today: fixedToday)
    model.phoneNumber = "+1 555 01" // six digits — wrong side
    #expect(!model.canSendCode)
    model.phoneNumber = "+1 555 013" // seven — right side
    #expect(model.canSendCode)
    model.enterCode("48291") // five
    #expect(!model.canVerify)
    model.enterCode("4829134839") // pasted junk: capped at six, numeric only
    #expect(model.codeDigits == "482913")
    #expect(model.canVerify)
    model.enterCode("48a9!13")
    #expect(model.codeDigits == "48913")
}

// ── the birthday gate ──────────────────────────────────────────────────────

@MainActor
@Test func twelveIsBlockedTypedAndThirteenPasses() {
    // both sides of COPPA's line, one day apart in effect: born 2013-09-01
    // is 12 on the fixed today; born 2013-08-01 turned 13 that month
    let blocked = AccountModel(today: fixedToday)
    blocked.birthday = date(2013, 9, 1)
    var created = false
    blocked.createAccount(quiz: OnboardingModel()) { created = true }
    #expect(blocked.ageError?.code == .underAgeMinimum)
    #expect(!created)

    let allowed = AccountModel(today: fixedToday)
    allowed.birthday = date(2013, 8, 1)
    allowed.createAccount(quiz: OnboardingModel()) { created = true }
    #expect(allowed.ageError == nil)
    #expect(created) // no store wired → straight through
}

@MainActor
@Test func theEchoAndTheWireShapeAgreeOnTheDate() {
    let model = AccountModel(today: fixedToday)
    model.birthday = date(1999, 3, 9)
    #expect(model.age == 27)
    #expect(model.birthdayEcho() == "9 march 1999 \u{00B7} 27")
    #expect(model.birthYearMonth() == "1999-03") // the day is not persisted
    #expect(ProfileDraft.firstInvalidField(
        OnboardingModel().draft(birthYearMonth: model.birthYearMonth() ?? "")
    ) == nil)
}

@MainActor
@Test func theWheelIsBounded1930Through2012() {
    let range = AccountModel.birthdayRange
    #expect(calendar.component(.year, from: range.lowerBound) == 1930)
    #expect(calendar.component(.year, from: range.upperBound) == 2012)
}

@MainActor
@Test func theBatchWriteCarriesTheWholeQuizPrior() async {
    let quiz = OnboardingModel()
    quiz.toggle(.haircare)
    quiz.hairPattern = "3b"
    actor Written {
        var draft: ProfileDraft?
        func set(_ value: ProfileDraft) {
            draft = value
        }
    }
    let written = Written()
    let model = AccountModel(
        store: AccountStore(finish: { await written.set($0) }),
        today: fixedToday
    )
    model.birthday = date(1999, 3, 9)
    model.createAccount(quiz: quiz) {}
    await model.createTask?.value
    let draft = await written.draft
    #expect(draft?.birthYearMonth == "1999-03")
    #expect(draft?.domains == [.makeup, .skincare, .haircare])
    #expect(draft?.hairPattern == "3b")
}

@MainActor
@Test func aFailedFinishSpeaksInWordsNotARawError() async {
    let model = AccountModel(
        store: AccountStore(finish: { _ in throw URLError(.timedOut) }),
        today: fixedToday
    )
    model.birthday = date(1999, 3, 9)
    var created = false
    model.createAccount(quiz: OnboardingModel()) { created = true }
    await model.createTask?.value
    #expect(!created)
    #expect(model.creationError?.code == .offline)
    #expect(model.creationError?.userMessage.isEmpty == false)
}

@MainActor
@Test func loginModeLandsWithoutABirthday() {
    // returning users answer nothing again — apple goes straight through
    let model = AccountModel(mode: .login, today: fixedToday)
    model.chooseApple()
    #expect(model.stage == .method) // no birthday stage entered; the caller lands them
}
