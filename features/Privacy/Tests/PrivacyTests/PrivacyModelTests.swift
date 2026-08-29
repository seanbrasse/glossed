import DataKit
import Foundation
import Testing
@testable import Privacy

// The rules the screen encodes. Enforcement — RLS, the minor lock trigger —
// is proven by pgTAP against real Postgres.

private func store(
    load: @escaping @Sendable () async throws -> PrivacyScopes = { PrivacyScopes() },
    setScope: @escaping @Sendable (VisibilitySurface, PrivacyScope) async throws -> Void = { _, _ in },
    setDiscoverable: @escaping @Sendable (Bool) async throws -> Void = { _ in }
) -> PrivacyStore {
    PrivacyStore(load: load, setScope: setScope, setDiscoverable: setDiscoverable)
}

@MainActor
@Test func aFreshAccountLoadsAsOnlyYou() async {
    // The default the RPC returns for a user with no row. The screen must show
    // private rather than empty — a blank privacy screen invites the reader to
    // assume nothing is set, which is the opposite of the truth.
    let model = PrivacyModel(store: store())
    await model.load()
    #expect(model.summaryLine == "only you")
    #expect(!model.scopes.discoverable)
}

@MainActor
@Test func mixedRowsSayMixedRatherThanRounding() async {
    let model = PrivacyModel(store: store(load: {
        PrivacyScopes(shelf: .publicScope, rankings: .onlyYou, routines: .onlyYou)
    }))
    await model.load()
    // Not "public" (which would overstate exposure to someone whose rankings
    // are private) and not "only you" (which would hide that a shelf is out
    // there). Both are lies; mixed is the answer.
    #expect(model.summaryLine == "mixed")
}

@MainActor
@Test func aFailedWriteRevertsTheRow() async {
    // The one lie this screen must never tell. An optimistic update that
    // survives a failed write leaves the screen claiming a shelf is private
    // while the database still says public.
    struct Boom: Error {}
    let model = PrivacyModel(store: store(setScope: { _, _ in throw Boom() }))
    await model.load()
    await model.setScope(.shelf, to: .publicScope)
    #expect(model.scopes.shelf == .onlyYou)
    #expect(model.errorMessage != nil)
}

@MainActor
@Test func aSuccessfulWriteKeepsTheNewValue() async {
    let model = PrivacyModel(store: store())
    await model.load()
    await model.setScope(.shelf, to: .friends)
    #expect(model.scopes.shelf == .friends)
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func changingOneRowLeavesTheOthersAlone() async {
    // A write that reset its neighbours would silently publish or hide
    // surfaces the user never touched.
    let model = PrivacyModel(store: store(load: {
        PrivacyScopes(shelf: .publicScope, rankings: .friends, routines: .onlyYou)
    }))
    await model.load()
    await model.setScope(.routines, to: .publicScope)
    #expect(model.scopes.shelf == .publicScope)
    #expect(model.scopes.rankings == .friends)
    #expect(model.scopes.routines == .publicScope)
}

@MainActor
@Test func discoverableIsNotAScopeAndDoesNotMoveThem() async {
    // §1.3: being visible and wanting to be surfaced are different decisions.
    let model = PrivacyModel(store: store(load: { PrivacyScopes(shelf: .publicScope) }))
    await model.load()
    await model.setDiscoverable(true)
    #expect(model.scopes.discoverable)
    #expect(model.scopes.shelf == .publicScope)
    #expect(model.summaryLine == "mixed") // unchanged by the switch
}

@MainActor
@Test func aFailedDiscoverableWriteRevertsToo() async {
    struct Boom: Error {}
    let model = PrivacyModel(store: store(setDiscoverable: { _ in throw Boom() }))
    await model.load()
    await model.setDiscoverable(true)
    #expect(!model.scopes.discoverable)
}

@MainActor
@Test func anAgeGateRefusalLocksTheScreen() async {
    // A minor's write is refused by the database. Without the lock they tap a
    // control that silently refuses, over and over, with no explanation.
    let model = PrivacyModel(store: store(setScope: { _, _ in
        throw GlossedError(.underAgeMinimum, userMessage: "your account is private while you're under 18.")
    }))
    await model.load()
    await model.setScope(.shelf, to: .publicScope)
    #expect(model.isLockedByAgeGate)
    #expect(model.scopes.shelf == .onlyYou)
}

@MainActor
@Test func anOrdinaryFailureDoesNotLockTheScreen() async {
    // Only the age gate locks. A dropped connection must stay retryable —
    // locking on any error would strand a user offline for the session.
    struct Boom: Error {}
    let model = PrivacyModel(store: store(setScope: { _, _ in throw Boom() }))
    await model.load()
    await model.setScope(.shelf, to: .publicScope)
    #expect(!model.isLockedByAgeGate)
}

@Test func looksHasNoRowYet() {
    // The column ships so Phase 2 inherits a tested one, but there are no looks
    // to scope — a row governing nothing is a promise the app cannot keep.
    #expect(PrivacyRow.allCases.count == 3)
    #expect(!PrivacyRow.allCases.map(\.surface).contains(.looks))
}

@Test func everyRowNamesWhatItExposes() {
    // Vague copy on a privacy screen is a way of not answering the question.
    for row in PrivacyRow.allCases {
        #expect(row.title == row.title.lowercased())
        #expect(row.detail.count > 20)
        #expect(row.detail == row.detail.lowercased())
    }
}
