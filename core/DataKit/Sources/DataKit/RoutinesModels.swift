import Foundation

// Split from `RoutinesRepository.swift` for the 300-line file ceiling when the
// owner-side reads landed (GLO-230) — a mechanical move, nothing renamed. Same
// reason `ShelfRow.swift` left `Models.swift`.

// `RoutineSlot` is NOT declared here — it already exists in `BrowseModels.swift`,
// mirroring `routine_slot` from `20260828000003_ranking.sql:4`. Redeclaring it
// is how this file was first written, and the compiler caught it; a second copy
// would have been a second place for the wire words to drift.

/// A routine as the composer hands it over, in one shape — the repository
/// writes parent and steps itself, so a caller cannot invent an ordering that
/// leaves a stepless routine behind on a mid-flight failure.
public struct RoutineDraft: Sendable {
    /// One step: the shelf row it runs, and the owner's words on what they do
    /// with it (0052 — "three drops, pressed in", not a second title). The
    /// note is optional and trimmed by the repository; 500 is the schema's
    /// bound and the composer's cap should match it.
    public struct Step: Sendable {
        public let userItemID: UUID
        public let note: String?

        public init(userItemID: UUID, note: String? = nil) {
            self.userItemID = userItemID
            self.note = note
        }
    }

    public let title: String
    public let slot: RoutineSlot
    /// In the order they should run. A routine is a sequence of things you
    /// OWN — the schema says so, with `routine_steps.user_item_id`
    /// referencing `user_items`, never `products` or `variants`.
    public let steps: [Step]
    /// Idempotency, the LookDraft pattern: the caller mints the routine's
    /// PRIMARY KEY, so a retry after a failed save upserts the same row rather
    /// than minting a second routine with the same name.
    public let routineID: UUID

    public init(
        title: String,
        slot: RoutineSlot,
        steps: [Step],
        routineID: UUID = UUID()
    ) {
        self.title = title
        self.slot = slot
        self.steps = steps
        self.routineID = routineID
    }
}

/// One of YOUR OWN routines, steps included.
///
/// Distinct from `BrowseRoutine` on purpose, and the difference is the title.
/// `BrowseRoutine.title` is the approved `public_texts` body — what strangers
/// are allowed to read. This one is `routines.title`, the column, which only
/// the owner can select at all (`routines_own`). Collapsing the two would put
/// an unreviewed title one field-access away from a public surface.
public struct MyRoutine: Sendable, Equatable, Identifiable {
    public let routineID: UUID
    public let title: String
    public let slot: RoutineSlot
    public let startedOn: Date?
    public let createdAt: Date
    /// In `position` order, always — see `assemble`.
    public let steps: [RoutineStep]

    public var id: UUID {
        routineID
    }

    /// The n behind the kit's "N steps · since". Derived, never carried
    /// alongside the array, so a count cannot disagree with the thing counted.
    public var stepN: Int {
        steps.count
    }

    public init(
        routineID: UUID, title: String, slot: RoutineSlot,
        startedOn: Date?, createdAt: Date, steps: [RoutineStep]
    ) {
        self.routineID = routineID
        self.title = title
        self.slot = slot
        self.startedOn = startedOn
        self.createdAt = createdAt
        self.steps = steps
    }
}
