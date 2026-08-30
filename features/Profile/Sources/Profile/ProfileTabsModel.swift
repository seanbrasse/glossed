import DataKit
import Foundation

/// The tab strip's state, and the copy each card wears.
@MainActor
@Observable
public final class ProfileTabsModel {
    public var tab: ProfileTab = .routines
    public var isEditing = false
    public var renaming: RenameTarget?
    public private(set) var routines: [MyRoutine] = []
    public private(set) var collections: [ProfileCollection] = []
    public private(set) var isLoading = true
    public private(set) var isSavingRename = false
    public private(set) var errorMessage: String?

    private let routinesStore: ProfileRoutinesStore?
    private let collectionsStore: ProfileCollectionsStore?

    public init(routines: ProfileRoutinesStore?, collections: ProfileCollectionsStore? = nil) {
        routinesStore = routines
        collectionsStore = collections
    }

    /// Only the tabs that have a seam behind them, in the frame's order.
    public var tabs: [ProfileTab] {
        ProfileTab.allCases.filter { available($0) }
    }

    private func available(_ tab: ProfileTab) -> Bool {
        switch tab {
        case .routines: routinesStore != nil
        case .collections: collectionsStore != nil
        }
    }

    /// Both tabs load together, because the segmented control switches between
    /// two things that are already there — a tab that starts a fetch when it is
    /// tapped puts a spinner behind a control that reads as instant.
    ///
    /// One failure does not blank the other tab: each read keeps whatever it
    /// got, and the first message wins. A user with routines and a collections
    /// read that timed out should still see their routines.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        if let routinesStore {
            do {
                routines = try await routinesStore.mine()
            } catch {
                note(error, fallback: "couldn't load your routines. pull to try again.")
            }
        }
        if let collectionsStore {
            do {
                collections = try await collectionsStore.mine()
            } catch {
                note(error, fallback: "couldn't load your collections. pull to try again.")
            }
        }
        // The frame opens on `routines`; if that tab was never wired, open on
        // the one that was rather than on a blank pane.
        if !available(tab), let first = tabs.first {
            tab = first
        }
    }

    private func note(_ error: Error, fallback: String) {
        guard errorMessage == nil else { return }
        errorMessage = (error as? GlossedError)?.userMessage ?? fallback
    }

    // MARK: - Edit mode (the frame's `edit profile` / `done editing`)

    /// Whether the tab now showing has anything to rename. The button is not
    /// drawn otherwise: an `edit profile` that turns nothing into a target is
    /// a control that does nothing, and this project has shipped that already.
    public var canEdit: Bool {
        renameWrite(for: tab) != nil
    }

    public var editButtonLabel: String {
        isEditing ? "done editing" : "edit profile"
    }

    /// The frame's mono hint, shown only while editing.
    public var editHint: String? {
        isEditing ? "tap any card to rename it" : nil
    }

    public func toggleEditing() {
        isEditing.toggle()
        if !isEditing {
            renaming = nil
        }
    }

    public func beginRename(_ target: RenameTarget) {
        guard isEditing, renameWrite(for: tab) != nil else { return }
        errorMessage = nil
        renaming = target
    }

    private func renameWrite(for tab: ProfileTab) -> (@Sendable (UUID, String) async throws -> Void)? {
        switch tab {
        case .routines: routinesStore?.rename
        case .collections: collectionsStore?.rename
        }
    }

    /// Writes the new title, then updates the row in place.
    ///
    /// In place rather than by reloading: the write returned, so the stored
    /// title is the trimmed string that was sent, and a reload would flash a
    /// spinner over a list that is already correct. The trim is done here as
    /// well as in the repository so the two cannot disagree about what landed.
    ///
    /// A blank title is refused before the round trip, in the repository's own
    /// words — `routines.title` is `not null` but has no length check, and a
    /// routine with a blank name is unaddressable in a list.
    public func saveRename() async {
        guard let target = renaming, let write = renameWrite(for: target.tabForKind) else { return }
        let trimmed = target.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "give it a name."
            return
        }
        isSavingRename = true
        defer { isSavingRename = false }
        errorMessage = nil
        do {
            try await write(target.id, trimmed)
            apply(trimmed, to: target)
            renaming = nil
        } catch {
            // The sheet stays open with what was typed. A rename that closes
            // on failure loses the words and tells you it worked.
            errorMessage = (error as? GlossedError)?.userMessage ?? "that didn't save. try again."
        }
    }

    private func apply(_ title: String, to target: RenameTarget) {
        switch target.kind {
        case .routine:
            routines = routines.map {
                guard $0.routineID == target.id else { return $0 }
                return MyRoutine(
                    routineID: $0.routineID, title: title, slot: $0.slot,
                    startedOn: $0.startedOn, createdAt: $0.createdAt, steps: $0.steps
                )
            }
        case .collection:
            collections = collections.map {
                guard $0.id == target.id else { return $0 }
                return ProfileCollection(id: $0.id, title: title, tint: $0.tint, itemN: $0.itemN)
            }
        }
    }

    /// The frame's `mono(r.steps.length + ' steps · ' + r.since)`.
    ///
    /// **`since` diverges, and it has to.** The kit's fixture writes freeform
    /// cadence copy — `started week 3`, `twice a week`, `every 5 days` — and
    /// no column carries any of it. What `routines` does carry is the slot and
    /// `started_on`, so the line states those and stops. Inventing the kit's
    /// phrasing would be a routine describing a schedule nobody set.
    public nonisolated static func stepsLine(_ routine: MyRoutine) -> String {
        var parts = [
            "\(routine.stepN) \(routine.stepN == 1 ? "step" : "steps")",
            slotWord(routine.slot)
        ]
        if let since = sinceWord(routine.startedOn) {
            parts.append("since \(since)")
        }
        return parts.joined(separator: " · ")
    }

    /// The kit's words for the four slots — `am` · `pm` · `weekly` ·
    /// `wash day`.
    ///
    /// `RoutineSlot.label` says `morning` / `evening` instead, which is
    /// **GLO-210**: the composer, browse and the kit disagree, and the fix is
    /// two lines in DataKit. DataKit is frozen to this lane, so the kit's
    /// words are mapped here rather than shipped wrong. **Delete this when
    /// GLO-210 lands** and call `slot.label` — the ticket is the licence for
    /// the duplication, not an excuse to keep it.
    nonisolated static func slotWord(_ slot: RoutineSlot) -> String {
        switch slot {
        case .am: "am"
        case .pm: "pm"
        case .weekly: "weekly"
        case .washDay: "wash day"
        }
    }

    /// Month and year, lowercase.
    ///
    /// Read in UTC on purpose: `started_on` is a Postgres `date`, and a bare
    /// calendar day rendered in the device's zone walks back a month for
    /// anyone west of Greenwich. The month words are the app's own rather than
    /// a `DateFormatter`'s, which keeps the copy lowercase without a
    /// locale-dependent `lowercased()` — and keeps this helper `Sendable`,
    /// since `DateFormatter` is not.
    nonisolated static func sinceWord(_ date: Date?) -> String? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let parts = calendar.dateComponents([.month, .year], from: date)
        guard let month = parts.month, let year = parts.year, months.indices.contains(month - 1) else {
            return nil
        }
        return "\(months[month - 1]) \(year)"
    }

    nonisolated static let months = [
        "jan", "feb", "mar", "apr", "may", "jun",
        "jul", "aug", "sep", "oct", "nov", "dec"
    ]

    /// The frame's `mono(c.count + ' products')`, singular at one.
    nonisolated static func productsLine(_ n: Int) -> String {
        "\(n) \(n == 1 ? "product" : "products")"
    }

    /// One step, named by the thing you own. `brand · product · shade`, and
    /// the shade only when the row has one — a step that prints an empty
    /// separator reads as a missing fact rather than an absent one.
    nonisolated static func stepLine(_ step: RoutineStep) -> String {
        [step.brandName, step.productName, step.variantLabel]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
