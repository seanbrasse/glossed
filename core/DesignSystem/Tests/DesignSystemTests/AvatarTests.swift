import Testing
@testable import DesignSystem

// The initial rule — the only logic the Avatar carries.

@Test func theInitialIsTheFirstCharacterLowercased() {
    #expect(Avatar.initialLetter(for: "maya") == "m")
    #expect(Avatar.initialLetter(for: "Élodie") == "é")
    #expect(Avatar.initialLetter(for: "  Juli ") == "j")
}

@Test func aNamelessAvatarShowsAQuestionMarkNotAnEmptyCircle() {
    #expect(Avatar.initialLetter(for: "") == "?")
    #expect(Avatar.initialLetter(for: "   ") == "?")
}
