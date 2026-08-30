import DataKit
import Foundation
import Observation

/// One "rank it" tap, from the shelf row that was tapped to the positions the
/// session writes back.
///
/// The caller hands over a `user_item_id` and nothing else. Everything the
/// session needs — which category, how long its wear-in is, what it unlocks at,
/// which of your other items are eligible — is read from that row, so the host
/// screen does not have to know the ranking rules in order to open the screen
/// that enforces them.
@MainActor
@Observable
public final class RankSessionModel {
    public enum State: Equatable {
        case loading
        /// Fewer eligible items than this category unlocks at. Said out loud
        /// rather than hidden: the leaderboard's law — a thing that cannot be
        /// ranked yet says so — is the same law here, and PRD §03 makes the
        /// unlock "a reward, never a required step", which only reads as a
        /// reward if you can see it coming.
        case locked(have: Int, need: Int)
        case ready(FaceOffSession)
        /// We could not load. Never a placement, and never "locked": a failed
        /// read is not a fact about how much you own.
        case unavailable(String)
    }

    public private(set) var state: State = .loading
    /// Set only when the write failed. The placement on screen is optimistic —
    /// the same optimism the fit control has — so this is what stops a
    /// celebration standing in for a save that never landed.
    public private(set) var saveFailure: String?
    /// The eligible rows, in the order the session compares them, so the host
    /// can draw a card for a contender without a second read.
    public private(set) var rows: [ShelfRow] = []
    public private(set) var categoryLabel = ""

    private let userItemID: UUID
    private let store: RankingStore
    private let now: Date
    private var categoryID: UUID?
    var loadTask: Task<Void, Never>?
    var saveTask: Task<Void, Never>?

    public init(userItemID: UUID, store: RankingStore, now: Date = Date()) {
        self.userItemID = userItemID
        self.store = store
        self.now = now
    }

    /// Statuses that can honestly answer "which do you reach for?".
    ///
    /// `want_to_try` cannot: you have not reached for it. Including it would
    /// let a wishlist outrank the things you actually use, which is the one
    /// way a personal ranking can be wrong about its own owner.
    static let rankableStatuses: Set<ItemStatus> = [.own, .finished, .repurchased]

    public func load() {
        loadTask?.cancel()
        loadTask = Task {
            do {
                let shelf = try await store.shelf()
                guard let candidate = shelf.first(where: { $0.userItemID == userItemID }) else {
                    // The row is gone. Not a lock and not a placement.
                    state = .unavailable("that item isn't on your shelf any more")
                    return
                }
                categoryLabel = candidate.categoryLabel
                let categories = try await store.categories(candidate.domain)
                guard !Task.isCancelled else { return }
                guard let category = categories.first(where: { $0.slug == candidate.categorySlug }) else {
                    state = .unavailable("couldn't read this category's ranking rules just now")
                    return
                }
                categoryID = category.id
                apply(category: category, to: shelf)
            } catch {
                guard !Task.isCancelled else { return }
                state = .unavailable(Self.message(error, fallback: "couldn't open a face-off just now"))
            }
        }
    }

    /// Eligibility, the unlock gate, and the list to insert into — in that
    /// order, because each depends on the one before it.
    private func apply(category: DataKit.Category, to shelf: [ShelfRow]) {
        let eligible = shelf
            .filter { $0.categorySlug == category.slug }
            .filter { Self.rankableStatuses.contains($0.status) }
            .filter {
                RankingRules.isPastWearIn(
                    startedOn: $0.startedOn,
                    wearInDays: category.wearInDays,
                    now: now
                )
            }
            // Already-ranked items keep their order; the rest join at the end
            // in the order they were logged. An unpositioned item is not
            // unrankable — it simply has not had its turn yet, and a session
            // that refused to compare against it would ask nothing on a shelf
            // where nothing has been ranked before.
            .sorted { lhs, rhs in
                let left = lhs.rankPosition ?? Int.max
                let right = rhs.rankPosition ?? Int.max
                return left == right ? lhs.loggedAt < rhs.loggedAt : left < right
            }
        rows = eligible
        guard RankingRules.isUnlocked(
            eligibleItemCount: eligible.count,
            minimum: category.rankUnlockMin
        ) else {
            state = .locked(have: eligible.count, need: category.rankUnlockMin)
            return
        }
        state = .ready(FaceOffSession(
            categoryID: category.id,
            categoryLabel: category.label,
            candidate: userItemID,
            rankedItemIDs: eligible.map(\.userItemID).filter { $0 != userItemID }
        ))
    }

    /// Writes the session. The comparisons and the positions go together in one
    /// RPC — a run of answers with no ordering behind it is a session the user
    /// would have to sit through again.
    public func finish(_ outcome: FaceOffSession.Outcome) {
        guard let categoryID else { return }
        saveFailure = nil
        saveTask = Task { [previous = saveTask] in
            await previous?.value
            do {
                try await store.apply(
                    outcome.comparisons.map {
                        FaceOffRecord(
                            categoryID: categoryID,
                            winnerItemID: $0.winnerItemID,
                            loserItemID: $0.loserItemID,
                            skipped: $0.skipped
                        )
                    },
                    outcome.orderedItemIDs.enumerated().map {
                        RankPosition(
                            categoryID: categoryID,
                            userItemID: $1,
                            position: $0 + 1
                        )
                    }
                )
            } catch {
                saveFailure = Self.message(error, fallback: "couldn't save this ranking just now")
            }
        }
    }

    /// What a contender is called. "pocket blush · freckle" in the frame — the
    /// variant only when the catalog returns one, never a stray separator
    /// standing in for a shade it does not have (GLO-63).
    public func name(of itemID: UUID) -> String {
        guard let row = rows.first(where: { $0.userItemID == itemID }) else { return "" }
        return [row.productName, row.variantLabel].compactMap(\.self).joined(separator: " · ")
    }

    public func row(_ itemID: UUID) -> ShelfRow? {
        rows.first { $0.userItemID == itemID }
    }

    static func message(_ error: any Error, fallback: String) -> String {
        (error as? GlossedError)?.userMessage ?? fallback
    }
}
