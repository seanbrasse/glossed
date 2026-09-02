import DataKit
import Foundation

/// What the stylist asks of the world, as closures. `send` is the only
/// required seam; the rest are optional and **nil hides the affordance** — a
/// routine card without `saveRoutine` shows no save, a product row without
/// `imageURL` shows the drawn mock.
public struct StylistStore: Sendable {
    public var send: @Sendable (_ transcript: [StylistTranscriptTurn]) async throws -> StylistReply
    public var saveRoutine: (@Sendable (_ draft: RoutineDraftBlock) async throws -> UUID)?
    public var imageURL: (@Sendable (_ catalogKey: String) -> URL?)?
    public var track: (@Sendable (_ toolsUsed: [String], _ answered: Bool) -> Void)?

    public init(send: @escaping @Sendable ([StylistTranscriptTurn]) async throws -> StylistReply) {
        self.send = send
    }

    /// The live seam over the `stylist` Edge Function (DataKit's opaque
    /// transport; this feature owns the shapes) and `RoutinesRepository`
    /// for the save. `imageURL` and `track` are the app's to add.
    public static func live(client: GlossedClient, routines: RoutinesRepository) -> StylistStore {
        var store = StylistStore(send: { transcript in
            let body = try JSONEncoder().encode(StylistTurnRequest(messages: transcript))
            do {
                let data = try await client.invokeEdgeFunctionForData("stylist", jsonBody: body)
                return try StylistReply.decode(data)
            } catch let error as GlossedError {
                // The function's refusals arrive as HTTP errors whose
                // detail carries its JSON; the two we route on are stated
                // by name so a wording change cannot silently turn a
                // "not yet" into "something broke".
                let detail = error.debugDetail ?? ""
                if detail.contains("not_yet") {
                    throw StylistError.notYet
                }
                if detail.contains("not configured") {
                    throw StylistError.unconfigured
                }
                throw error
            }
        })
        store.saveRoutine = { draft in
            guard let slot = RoutineSlot(rawValue: draft.slot) else {
                throw GlossedError(.invalidInput, userMessage: "that routine has no time of day.")
            }
            return try await routines.saveDraft(RoutineDraft(
                title: draft.title,
                slot: slot,
                steps: draft.steps.map { RoutineDraft.Step(userItemID: $0.userItemID, note: $0.note) }
            ))
        }
        return store
    }
}
