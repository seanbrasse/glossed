import DataKit
import Foundation

public struct TrendingStore: Sendable {
    public var load: @Sendable (String?, Int) async throws -> [TrendingVariant]

    public init(load: @escaping @Sendable (String?, Int) async throws -> [TrendingVariant]) {
        self.load = load
    }

    public static func live(_ repository: BrowseRepository) -> TrendingStore {
        TrendingStore(load: { try await repository.trending(skinType: $0, limit: $1) })
    }
}

@MainActor
@Observable
public final class TrendingModel {
    public private(set) var rows: [TrendingVariant] = []
    public private(set) var isLoading = true
    public private(set) var errorMessage: String?

    /// nil = everyone. Any other value is a cohort, and the header must name it.
    public private(set) var skinType: String?

    private let store: TrendingStore

    public init(store: TrendingStore, skinType: String? = nil) {
        self.store = store
        self.skinType = skinType
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rows = try await store.load(skinType, 20)
        } catch {
            errorMessage = (error as? GlossedError)?.userMessage ?? "couldn't load trending."
        }
    }

    public func setCohort(_ skinType: String?) async {
        self.skinType = skinType
        await load()
    }

    /// Names whose n this is (`domain.md` §5). Derived from the same value that
    /// built the query, so the label cannot drift from the filter.
    public var cohortLine: String {
        skinType.map { "among people with \($0) skin" } ?? "among everyone"
    }

    /// The window every count on this screen is over. A velocity claim without
    /// its period says nothing.
    public var windowLine: String {
        guard let days = rows.first?.windowDays else { return "" }
        return "in the last \(days) days"
    }

    public var isEmpty: Bool {
        !isLoading && rows.isEmpty
    }

    /// True when nothing has cleared the threshold yet — a young surface, not a
    /// broken one. The rows still render with their counts.
    public var allBelowThreshold: Bool {
        !rows.isEmpty && rows.allSatisfy { !$0.meetsMinN }
    }
}
