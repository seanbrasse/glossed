import SwiftUI
import Testing
@testable import DesignSystem

// GLO-57: the choice moved from the call site into the primitive, and the
// default is the whole point. These pin the default rather than the rendering
// — a view modifier has no return value to assert, but a default does, and a
// default flipped back is exactly how this regresses.

@Test func aTextFieldIsPlainUnlessItAsksNotToBe() {
    // Names, handles, queries and codes are every field this app has. Left on
    // the system default, "laneige" autocorrects to "lineage" and the search
    // misses a product we stock.
    let field = GlossedInput("brand, product, shade…", text: .constant(""))
    #expect(field.typing == .plain)
}

@Test func proseHasToSaySoAndCanStillSayIt() {
    // The escape hatch exists — the point is that forgetting now yields the
    // safe answer instead of the dangerous one.
    let prose = GlossedInput("say something", text: .constant(""), typing: .sentences)
    #expect(prose.typing == .sentences)
}

@Test func theKeyboardHintIsUnaffectedByTheTypingChoice() {
    // Two separate axes: a phone pad has no autocapitalisation to disable, and
    // a plain field can still want a numeric keyboard.
    let phone = GlossedInput("+1 555 0134", text: .constant(""), keyboard: .phone)
    #expect(phone.typing == .plain)
    #expect(phone.keyboard == .phone)
}
