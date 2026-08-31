import DataKit
import Foundation
import Testing
@testable import Collections

/// The composer's decisions, none of which need a client.
@MainActor
struct CollectionComposerModelTests {
    private func item(_ name: String) -> CollectionItem {
        CollectionItem(id: UUID(), name: name, brand: "a brand")
    }

    @Test func aNameIsTheOnlyThingSavingRequires() {
        let model = CollectionComposerModel()
        #expect(model.canSave == false)
        model.title = "   "
        #expect(model.canSave == false, "whitespace is not a name")
        model.title = "holy grails only"
        #expect(model.canSave, "a collection with no products is one you named on purpose")
    }

    @Test func pickingTwiceTakesItBackOut() {
        let model = CollectionComposerModel()
        let row = item("pro filt'r soft matte")
        model.toggle(row)
        #expect(model.isPicked(row))
        model.toggle(row)
        #expect(model.isPicked(row) == false)
        #expect(model.picked.isEmpty)
    }

    @Test func theOrderYouTapInIsTheOrderItKeeps() {
        let model = CollectionComposerModel()
        let first = item("first")
        let second = item("second")
        model.toggle(first)
        model.toggle(second)
        #expect(model.picked.map(\.name) == ["first", "second"])
    }

    @Test func theSummarySaysWhatSavingWillDo() {
        let model = CollectionComposerModel()
        #expect(model.summary == "name it — the products are optional")
        model.title = "spring"
        #expect(model.summary == "empty for now", "zero is stated, not hidden")
        model.toggle(item("one"))
        #expect(model.summary == "1 product")
        model.tint = .mint
        #expect(model.summary == "1 product · mint")
    }

    /// The half-written case: the collection exists, so the warning has to
    /// name it and say what is missing rather than offering a retry that
    /// would mint a second one.
    @Test func aPartialSaveNamesTheCollectionAndTheCount() {
        #expect(CollectionComposerModel.partialWarning(name: "spring", missed: 1)
            .contains("made spring"))
        #expect(CollectionComposerModel.partialWarning(name: "spring", missed: 1)
            .contains("1 product didn't go in"))
        #expect(CollectionComposerModel.partialWarning(name: "spring", missed: 3)
            .contains("3 products didn't go in"))
    }

    /// With no store wired the screen still closes — it does not hang on a
    /// save that can never return.
    @Test func savingWithNoStoreStillFinishes() {
        let model = CollectionComposerModel()
        model.title = "spring"
        var finished = false
        model.save { warning in
            finished = true
            #expect(warning == nil)
        }
        #expect(finished)
    }

    @Test func anEmptyShelfLoadsRatherThanHanging() {
        let model = CollectionComposerModel()
        model.loadShelf()
        #expect(model.isLoadingShelf == false)
        #expect(model.shelf.isEmpty)
    }
}
