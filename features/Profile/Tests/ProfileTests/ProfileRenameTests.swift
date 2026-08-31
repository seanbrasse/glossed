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
    #expect(!model.canRename)
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

private func aCollection(title: String = "wash day kit") -> ProfileCollection {
    ProfileCollection(id: UUID(), title: title, tint: "mint", itemN: 6, visibility: .onlyYou)
}

// MARK: - Edit mode gating (GLO-271, sweep finding 05)

@MainActor
@Test func anEmptyCollectionsTabOffersNothingToRename() async {
    // The defect this replaces: `canEdit` switched on the tab KIND and never
    // on its contents, so `edit profile` drew over `no collections yet` and
    // edit mode then said `tap any card to rename it` with no cards on
    // screen. The old doc comment claimed it prevented exactly that.
    // A writer IS wired — emptiness alone is what withholds the control, so
    // this cannot pass for the wrong reason.
    let model = ProfileTabsModel(
        collections: ProfileCollectionsStore(mine: { [] }, rename: { _, _ in })
    )
    await model.load()
    #expect(model.canRename == false)
    model.isEditing = true
    #expect(model.editHint == nil)
}

@MainActor
@Test func acollectionsTabWithRowsCanRenameAndSaysSo() async {
    let model = ProfileTabsModel(
        collections: ProfileCollectionsStore(mine: { [aCollection()] }, rename: { _, _ in })
    )
    await model.load()
    #expect(model.canRename)
    model.isEditing = true
    #expect(model.editHint == "tap any card to rename it")
}

@MainActor
@Test func renameIsRefusedWhenNothingCanWriteThatKind() async {
    // The guard follows the target's writer, not the tab showing. With no
    // collections store wired at all there is nothing to write through, so
    // the sheet must not open.
    let model = ProfileTabsModel(routines: ProfileRoutinesStore(mine: { [] }, rename: { _, _ in }))
    await model.load()
    model.isEditing = true
    model.beginRename(RenameTarget(kind: .collection, id: UUID(), value: "holy grails only"))
    #expect(model.renaming == nil)
}

// MARK: - The identity fields edit profile offers

@Test func identityOffersNameAndBioAndNotAPhoto() {
    // The photo is absent on purpose: there is no photo column in the schema
    // (`profiles` carries `avatar_seed` and no URL), so it waits on a
    // migration. A case here would be a door onto a room with no floor.
    #expect(ProfileIdentityField.allCases == [.name, .bio])
    #expect(ProfileIdentityField.name.label == "your name")
    #expect(ProfileIdentityField.bio.label == "your bio")
}
