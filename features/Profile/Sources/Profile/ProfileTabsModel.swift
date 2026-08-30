import DataKit
import Foundation

/// The profile's lower half — `G.Profile`'s `Segmented ['routines','collections']`
/// and whichever tab it selects (GLO-230).
///
/// The frame declares both options unconditionally because its data is a
/// fixture. Here the set is derived from the seams the app actually filled, so
/// a segment never appears in front of a surface that cannot answer: a tab
/// whose content is "coming soon" is the drawer's `collections land with
/// GLO-21` mistake wearing different words (GLO-189).
public enum ProfileTab: String, CaseIterable, Sendable {
    case routines, collections

    /// Lowercase, like every label in the app. The kit's segment words are
    /// the enum's own.
    public var label: String {
        rawValue
    }
}

/// How the profile's tabs reach persistence. Closures, not repositories, for
/// the reason `LooksStore` and `CollectionsStore` are: features never import
/// features, and the model is driven in tests with no client present.
public struct ProfileRoutinesStore: Sendable {
    public var mine: @Sendable () async throws -> [MyRoutine]

    public init(mine: @escaping @Sendable () async throws -> [MyRoutine]) {
        self.mine = mine
    }

    public static func live(_ routines: RoutinesRepository) -> ProfileRoutinesStore {
        ProfileRoutinesStore(mine: { try await routines.mine() })
    }
}

/// One card of the collections grid — the whole of what the frame draws, and
/// nothing more.
///
/// **A local shape rather than DataKit's `MyCollection`, deliberately.** The
/// two carry the same facts, but `MyCollection` also carries `visibility`, and
/// a field on a struct this screen renders is an invitation to write copy
/// about it. V1 creates every collection `only_you` and no surface here can
/// change, honour or truthfully report that — copy about a scope no screen
/// controls is the GLO-208 shape. What is not carried cannot be claimed.
///
/// `tint` is the wire word from `collections.cover_tint`, not a colour: the
/// column is nullable `text` with no check constraint, so an unrecognised
/// value is a real possibility and draws untinted rather than throwing.
public struct ProfileCollection: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let tint: String?
    /// The frame's `mono(c.count + ' products')`. A count of YOUR OWN
    /// collection — no cohort, no evidence chrome.
    public let itemN: Int

    public init(id: UUID, title: String, tint: String?, itemN: Int) {
        self.id = id
        self.title = title
        self.tint = tint
        self.itemN = itemN
    }
}

/// The collections half of the seam.
public struct ProfileCollectionsStore: Sendable {
    public var mine: @Sendable () async throws -> [ProfileCollection]

    public init(mine: @escaping @Sendable () async throws -> [ProfileCollection]) {
        self.mine = mine
    }
}

/// The tab strip's state, and the copy each card wears.
@MainActor
@Observable
public final class ProfileTabsModel {
    public var tab: ProfileTab = .routines
    public private(set) var routines: [MyRoutine] = []
    public private(set) var collections: [ProfileCollection] = []
    public private(set) var isLoading = true
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
