import DataKit
import Foundation
import Observation

/// The board's state (GLO-20): one category at a time, two scopes, two
/// directions. The evidence labels live here because they carry the
/// cohort-naming rule (domain.md §5) and deserve tests.
@MainActor
@Observable
public final class LeaderboardModel {
    public enum Scope: String, CaseIterable, Sendable {
        case yours, everyone

        /// "all" is the RPC's word for everyone; "yours" resolves server-side.
        var wire: String {
            self == .everyone ? "all" : "yours"
        }
    }

    public private(set) var rows: [LeaderboardRow] = []
    public private(set) var categories: [Category] = []
    public private(set) var isLoading = true
    public private(set) var selectedCategoryID: UUID
    public private(set) var domain: Domain
    public var scope: Scope = .everyone {
        didSet { load() }
    }

    /// The lowest board (PRD §10) — same data ascending, with the reasons.
    public var ascending = false {
        didSet { load() }
    }

    private let store: LeaderboardStore?
    var loadTask: Task<Void, Never>?

    public init(store: LeaderboardStore?, categoryID: UUID, domain: Domain) {
        self.store = store
        selectedCategoryID = categoryID
        self.domain = domain
    }

    public func select(categoryID: UUID) {
        selectedCategoryID = categoryID
        load()
    }

    public func load() {
        loadTask?.cancel()
        guard let store else {
            isLoading = false
            return
        }
        isLoading = rows.isEmpty
        loadTask = Task { [id = selectedCategoryID, wire = scope.wire, asc = ascending] in
            if categories.isEmpty {
                categories = (try? await store.categories(domain)) ?? []
            }
            let loaded = try? await store.rows(id, wire, asc)
            guard !Task.isCancelled, id == selectedCategoryID else { return }
            rows = loaded ?? []
            isLoading = false
        }
    }

    /// The rank a row renders, or nil for the "—" rows: only claimed rows
    /// count, in the order the RPC already put them.
    public func rank(of row: LeaderboardRow) -> Int? {
        guard row.isRankable else { return nil }
        return rows.prefix(while: { $0.id != row.id }).filter(\.isRankable).count + 1
    }

    /// Every claim names whose n it is (domain.md §5). The kit's fixture
    /// names the exact anchor ("face-offs in fenty 240"); the client does
    /// not know the anchor yet, so the cohort is named by kind.
    public func evidenceLabel() -> String {
        switch (scope, domain) {
        case (.everyone, _): "face-offs"
        case (.yours, .haircare): "face-offs · your type"
        case (.yours, _): "face-offs · your shade"
        }
    }

    public static func emptyLine(n: Int, needed: Int) -> String {
        "not enough face-offs yet · \(n) of \(needed)"
    }
}
