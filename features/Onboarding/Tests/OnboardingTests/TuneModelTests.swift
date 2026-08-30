import DataKit
import Foundation
import Testing
@testable import Onboarding

// The tune screen's rules: an edit, not a re-ask; empty is a fine answer;
// a failed save keeps the answers editable.

@MainActor
@Test func loadingStartsFromTheCurrentAnswers() async {
    let model = TuneModel(load: {
        TuneModel.Selection(skinType: .combo, concerns: ["texture"], brands: ["rhode"])
    })
    model.loadCurrent()
    await model.task?.value
    #expect(model.selection.skinType == .combo)
    #expect(model.selection.concerns == ["texture"])
    #expect(model.phase == .ready)
}

@MainActor
@Test func aFailedLoadStartsBlankRatherThanBlocking() async {
    let model = TuneModel(load: { throw URLError(.timedOut) })
    model.loadCurrent()
    await model.task?.value
    #expect(model.selection == TuneModel.Selection())
    #expect(model.phase == .ready) // tuning from scratch beats not tuning
}

@MainActor
@Test func concernsAndBrandsToggleFreelyIncludingToEmpty() {
    // unlike domains, empty is a fine answer here — the wrong-side fixture
    // of the never-empties rule
    let model = TuneModel()
    model.toggleConcern("acne")
    model.toggleConcern("texture")
    model.toggleConcern("acne")
    #expect(model.selection.concerns == ["texture"])
    model.toggleConcern("texture")
    #expect(model.selection.concerns.isEmpty)
    model.toggleBrand("rhode")
    model.toggleBrand("rhode")
    #expect(model.selection.brands.isEmpty)
}

@MainActor
@Test func saveHandsTheWholeSelectionToTheSeam() async {
    actor Saved {
        var selection: TuneModel.Selection?
        func set(_ value: TuneModel.Selection) {
            selection = value
        }
    }
    let saved = Saved()
    let model = TuneModel(save: { await saved.set($0) })
    model.selection = TuneModel.Selection(skinType: .dry, concerns: ["redness"], brands: ["kosas"])
    var landed = false
    model.saveSelection { landed = true }
    await model.task?.value
    let selection = await saved.selection
    #expect(selection?.skinType == .dry)
    #expect(selection?.brands == ["kosas"])
    #expect(landed)
    #expect(model.phase == .saved)
}

@MainActor
@Test func aFailedSaveKeepsTheAnswersAndSpeaksInWords() async {
    let model = TuneModel(save: { _ in throw URLError(.notConnectedToInternet) })
    model.selection.skinType = .oily
    var landed = false
    model.saveSelection { landed = true }
    await model.task?.value
    #expect(!landed)
    #expect(model.phase == .ready) // still editable
    #expect(model.selection.skinType == .oily) // nothing lost
    #expect(model.saveError?.code == .offline)
}

@Test func theConcernVocabularyIsTheKits() {
    #expect(TuneModel.concernOptions
        == ["acne", "texture", "redness", "dark spots", "fine lines", "dryness"])
}
