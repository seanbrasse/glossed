import Foundation
import Testing
@testable import Onboarding

// The tour's two slides and the words they carry — doctrine, not filler.

@MainActor
@Test func twoSlidesShelfThenDiscover() {
    let model = TourModel()
    #expect(TourModel.slides.count == 2)
    #expect(model.slide.tab == "shelf")
    #expect(model.next())
    #expect(model.slide.tab == "discover")
    #expect(!model.next()) // done — the caller owns the welcome
}

@MainActor
@Test func theNextButtonEndsWithTheKitsWords() {
    let model = TourModel()
    #expect(model.nextLabel == "next")
    _ = model.next()
    #expect(model.nextLabel == "take me in \u{273F}")
}

@Test func theStoriesCarryTheDoctrine() {
    // the two claims that must survive any copy edit: no stars, and
    // every claim shows its n
    #expect(TourModel.slides[0].story.contains("no stars"))
    #expect(TourModel.slides[1].story.contains("shows its n"))
    for slide in TourModel.slides {
        #expect(slide.story == slide.story.lowercased()) // house lowercase
        #expect(!slide.title.isEmpty)
    }
}

@MainActor
@Test func theTabsAreTheShellsOwnIds() {
    // the overlay hands these to the shell's nav — a rename there must
    // fail here before it silently points the finger at nothing
    #expect(Set(TourModel.slides.map(\.tab)) == ["shelf", "discover"])
}
