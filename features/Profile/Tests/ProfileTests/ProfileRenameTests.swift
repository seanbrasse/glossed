import DataKit
import Foundation
import Testing
@testable import Profile

// The rename half of the profile's edit mode, carried into the GLO-261
// redesign from #397 (GLO-230). Its own file so neither test file crosses
// SwiftLint's 300-line ceiling.

private func routine(title: String = "morning glass skin") -> MyRoutine {
    MyRoutine(
        routineID: UUID(), title: title, slot: .am,
        startedOn: nil, createdAt: Date(timeIntervalSince1970: 0), steps: []
    )
}

@MainActor
private func editableModel(
    routines: [MyRoutine], rename: @escaping @Sendable (UUID, String) async throws -> Void
) -> ProfileTabsModel {
    let model = ProfileTabsModel(
        routines: ProfileRoutinesStore(mine: { routines }, rename: rename)
    )
    model.tab = .routines
    return model
}

@MainActor
@Test func aRenameWritesTheTrimmedTitleAndUpdatesTheRowInPlace() async {
    let existing = routine(title: "am")
    nonisolated(unsafe) var wrote: String?
    let model = editableModel(routines: [existing], rename: { _, title in wrote = title })
    await model.load()
    model.toggleEditing()
    model.beginRename(RenameTarget(kind: .routine, id: existing.routineID, value: "  pm reset  "))
    await model.saveRename()
    #expect(wrote == "pm reset")
    #expect(model.routines.first?.title == "pm reset")
    #expect(model.renaming == nil)
}

@MainActor
@Test func aBlankTitleIsRefusedBeforeTheRoundTrip() async {
    nonisolated(unsafe) var writes = 0
    let model = editableModel(routines: [routine()], rename: { _, _ in writes += 1 })
    await model.load()
    model.toggleEditing()
    model.beginRename(RenameTarget(kind: .routine, id: UUID(), value: "   "))
    await model.saveRename()
    #expect(writes == 0)
    #expect(model.errorMessage == "give it a name.")
}

@MainActor
@Test func aFailedRenameKeepsTheSheetAndTheTypedWords() async {
    let existing = routine(title: "am")
    let model = editableModel(routines: [existing], rename: { _, _ in
        throw GlossedError(.offline, userMessage: "you're offline.")
    })
    await model.load()
    model.toggleEditing()
    model.beginRename(RenameTarget(kind: .routine, id: existing.routineID, value: "pm reset"))
    await model.saveRename()
    #expect(model.errorMessage == "you're offline.")
    #expect(model.renaming?.value == "pm reset")
    // And the list still says what the database says.
    #expect(model.routines.first?.title == "am")
}

@MainActor
@Test func neitherLooksNorShelfOffersARename() async {
    // Nothing renames a look or a shelf entry — `edit profile` on those tabs
    // would be a control that does nothing.
    let model = ProfileTabsModel(
        looks: ProfileLooksStore(mine: {
            [ProfileLook(id: UUID(), caption: "sunday", photoN: 2, isPublished: true)]
        }),
        shelf: ProfileShelfStore(mine: { [] })
    )
    await model.load()
    #expect(model.tab == .looks)
    #expect(!model.canEdit)
}

@Test func theEyebrowNamesWhatIsBeingRenamed() {
    // The kit builds it by uppercasing the tab key and dropping the trailing s.
    #expect(RenameTarget(kind: .routine, id: UUID(), value: "").eyebrow == "RENAME ROUTINE")
    #expect(RenameTarget(kind: .collection, id: UUID(), value: "").eyebrow == "RENAME COLLECTION")
}

@MainActor
@Test func theWriteFollowsTheTargetNotTheTabShowing() async {
    // A tab switched under an open sheet must not send a routine's id to the
    // collections rename.
    nonisolated(unsafe) var routineWrites = 0
    nonisolated(unsafe) var collectionWrites = 0
    let model = ProfileTabsModel(
        collections: ProfileCollectionsStore(mine: { [] }, rename: { _, _ in collectionWrites += 1 }),
        routines: ProfileRoutinesStore(mine: { [] }, rename: { _, _ in routineWrites += 1 })
    )
    model.tab = .routines
    model.toggleEditing()
    model.beginRename(RenameTarget(kind: .routine, id: UUID(), value: "am"))
    model.tab = .collections
    await model.saveRename()
    #expect(routineWrites == 1)
    #expect(collectionWrites == 0)
}
