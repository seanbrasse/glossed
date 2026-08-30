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
    public private(set) var categories: [DataKit.Category] = []
    public private(set) var isLoading = true
    /// Nil until the opening slug resolves against the loaded categories —
    /// and it stays nil when the slug names no category in the domain, which
    /// renders as an empty board, never a wrong one.
    public private(set) var selectedCategoryID: UUID?
    public let domain: Domain

    /// The frame opens scoped ("your shade") — the board's whole point is
    /// rank among people whose evidence transfers to you.
    public var scope: Scope = .yours {
        didSet { load() }
    }

    /// The lowest board (PRD §10) — same data ascending, with the reasons.
    public var ascending = false {
        didSet { load() }
    }

    private let store: LeaderboardStore?
    private let imageBase: URL?
    /// Both doors onto this screen hold a slug, not an id (`ShelfItem`
    /// carries `categorySlug`, `CatalogHit` both) — so the model resolves it
    /// against the pills it fetches anyway, and the screen opens instantly
    /// instead of waiting on a lookup before it can exist.
    private let openedFromSlug: String
    var loadTask: Task<Void, Never>?

    public init(
        store: LeaderboardStore?,
        categorySlug: String,
        domain: Domain,
        imageBase: URL? = nil
    ) {
        self.store = store
        openedFromSlug = categorySlug
        self.domain = domain
        self.imageBase = imageBase
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
        loadTask = Task { [wire = scope.wire, asc = ascending] in
            if categories.isEmpty {
                categories = await (try? store.categories(domain)) ?? []
            }
            if selectedCategoryID == nil {
                selectedCategoryID = categories.first { $0.slug == openedFromSlug }?.id
            }
            guard let id = selectedCategoryID else {
                guard !Task.isCancelled else { return }
                rows = []
                isLoading = false
                return
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

    /// The scoped segment's word for "people like you" — hair matches by
    /// type, everything else by shade.
    public var yoursOption: String {
        domain == .haircare ? "your type" : "your shade"
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

    public nonisolated static func emptyLine(n: Int, needed: Int) -> String {
        "not enough face-offs yet · \(n) of \(needed)"
    }

    /// The n a row renders. The label says "face-offs" and the min-n gate
    /// counts face-offs, so this is the face-off count — never `nUsers`,
    /// which the first drive showed on screen: a row with 21 face-offs from
    /// 13 users read "13 face-offs", a claim off by its own label.
    public nonisolated static func n(of row: LeaderboardRow) -> Int {
        row.hit.faceOffCount ?? 0
    }

    /// The footer rule line. The threshold comes off the rows (`needed`
    /// travels with every one) so the sentence cannot drift from the gate
    /// it describes; 5 is only the wordless-screen fallback.
    public var footerLine: String {
        let needed = rows.first?.needed ?? 5
        return "every row shows its n — a product needs \(needed) face-offs"
            + " in a scope before it can be ranked in it"
    }

    /// Storage key → fetchable URL, the shelf's composition rule: nil base or
    /// nil key degrades to the drawn mock, never a broken image (GLO-83).
    public func imageURL(for hit: CatalogHit) -> URL? {
        guard let imageBase, let key = hit.catalogImageKey else { return nil }
        return imageBase.appending(path: key)
    }
}
