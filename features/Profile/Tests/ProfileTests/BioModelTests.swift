import DataKit
import Foundation
import Testing
@testable import Profile

private func bio(_ body: String, _ state: ModerationState) throws -> PublicText {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "kind": "bio",
      "subject_id": null,
      "body": "\(body)",
      "state": "\(state.rawValue)"
    }
    """
    return try JSONDecoder().decode(PublicText.self, from: Data(json.utf8))
}

private func store(
    loading loaded: [PublicText?],
    onSave: @escaping @Sendable (String) -> Void = { _ in },
    failing: Bool = false
) -> BioStore {
    let cursor = Cursor(loaded)
    return BioStore(
        load: { cursor.next() },
        save: { body in
            if failing {
                throw GlossedError(.offline, userMessage: "no connection.")
            }
            onSave(body)
        }
    )
}

/// Hands back one canned read per call, so a test can say what the row looked
/// like before the write and what it looks like after.
private final class Cursor: @unchecked Sendable {
    private var values: [PublicText?]
    init(_ values: [PublicText?]) {
        self.values = values
    }

    func next() -> PublicText? {
        guard !values.isEmpty else { return nil }
        return values.removeFirst()
    }
}

@MainActor
@Test func theStatusLineComesFromTheRowRatherThanAnAssumption() async throws {
    // `bios_auto_approve()` (GLO-207) is a switch. A screen that hardcodes
    // "it's live" is correct only until someone flips it — and then it is a
    // screen promising visibility the profile query does not grant.
    let approved = try BioModel(store: store(loading: [bio("soft glam", .approved)]))
    await approved.load()
    #expect(approved.statusLine.contains("live on your profile"))

    let pending = try BioModel(store: store(loading: [bio("soft glam", .pending)]))
    await pending.load()
    #expect(pending.statusLine.contains("isn't on your profile yet"))

    let empty = BioModel(store: store(loading: [nil]))
    await empty.load()
    #expect(empty.statusLine == "nothing saved yet.")
}

@MainActor
@Test func savingRereadsSoTheScreenShowsWhatLandedNotWhatWasTyped() async throws {
    let model = try BioModel(store: store(loading: [nil, bio("soft glam", .approved)]))
    await model.load()
    model.typed = "  soft glam  "
    await model.save()
    // Trimmed on the way out, and re-read on the way back: the field shows the
    // stored body, not the whitespace the user happened to type.
    #expect(model.typed == "soft glam")
    #expect(model.statusLine.contains("live on your profile"))
}

@MainActor
@Test func aRefusedWriteIsStatedRatherThanSwallowed() async {
    // GLO-216's shape: a save that reports nothing on a refused write is how
    // linked socials looked correct while being dead.
    let model = BioModel(store: store(loading: [nil], failing: true))
    await model.load()
    model.typed = "soft glam"
    await model.save()
    #expect(model.errorMessage == "no connection.")
}

@MainActor
@Test func thereIsNothingToSaveUntilSomethingChanges() async throws {
    let model = try BioModel(store: store(loading: [bio("soft glam", .approved)]))
    await model.load()
    #expect(!model.canSave, "the saved body is not a change")
    model.typed = "   "
    #expect(!model.canSave, "whitespace is not a bio")
    model.typed = "soft glam, mostly"
    #expect(model.canSave)
}
