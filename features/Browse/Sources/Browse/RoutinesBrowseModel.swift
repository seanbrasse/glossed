import DataKit
import Foundation

public struct RoutinesStore: Sendable {
    public var browse: @Sendable (RoutineSlot, String?, String?) async throws -> [BrowseRoutine]
    public var detail: @Sendable (UUID) async throws -> RoutineDetail?

    public init(
        browse: @escaping @Sendable (RoutineSlot, String?, String?) async throws -> [BrowseRoutine],
        detail: @escaping @Sendable (UUID) async throws -> RoutineDetail?
    ) {
        self.browse = browse
        self.detail = detail
    }

    public static func live(_ repository: BrowseRepository) -> RoutinesStore {
        RoutinesStore(
            browse: { try await repository.routines(slot: $0, skinType: $1, hairPattern: $2) },
            detail: { try await repository.routineDetail(routineID: $0) }
        )
    }
}

@MainActor
@Observable
public final class RoutinesBrowseModel {
    public private(set) var rows: [BrowseRoutine] = []
    public private(set) var isLoading = true
    public private(set) var errorMessage: String?

    public private(set) var slot: RoutineSlot = .am
    public private(set) var skinType: String?
    public private(set) var hairPattern: String?

    private let store: RoutinesStore

    public init(store: RoutinesStore) {
        self.store = store
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rows = try await store.browse(slot, skinType, hairPattern)
        } catch {
            errorMessage = (error as? GlossedError)?.userMessage ?? "couldn't load routines."
        }
    }

    public func setSlot(_ slot: RoutineSlot) async {
        self.slot = slot
        // Hair pattern only narrows wash day; carrying it elsewhere would
        // filter by something the slot has no opinion about.
        if slot != .washDay {
            hairPattern = nil
        }
        await load()
    }

    public func setFilters(skinType: String?, hairPattern: String?) async {
        self.skinType = skinType
        self.hairPattern = slot == .washDay ? hairPattern : nil
        await load()
    }

    public var isEmpty: Bool {
        !isLoading && rows.isEmpty
    }

    /// Filters are Regulated values. They travel in the query because the
    /// database needs them, and must not reach an event beyond `filter_kind`.
    public var filterLine: String {
        let parts = [skinType.map { "\($0) skin" }, hairPattern.map { "\($0) hair" }].compactMap(\.self)
        return parts.isEmpty ? "from everyone" : "from people with " + parts.joined(separator: " · ")
    }

    /// One message for four exclusions — scope, discoverable, unapproved title,
    /// block. Naming which applied would leak the one that did.
    public var emptyLine: String {
        "no routines to show here yet."
    }
}

@MainActor
@Observable
public final class RoutineDetailModel {
    public private(set) var detail: RoutineDetail?
    public private(set) var isLoading = true

    private let store: RoutinesStore
    private let routineID: UUID

    public init(store: RoutinesStore, routineID: UUID) {
        self.store = store
        self.routineID = routineID
    }

    /// Nil covers "not visible" and "no such routine" alike, and the screen
    /// must not tell them apart.
    public var isUnavailable: Bool {
        !isLoading && detail == nil
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        detail = try? await store.detail(routineID)
    }

    /// The n behind the routine: how many steps the viewer can actually see.
    public var stepCount: Int {
        detail?.steps.count ?? 0
    }
}
