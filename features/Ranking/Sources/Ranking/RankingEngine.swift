import Foundation

/// Pure ranking logic. Deliberately knows nothing about the network or the
/// database: a list, some answers, a new list. That keeps the rules that decide
/// what a user's shelf *means* testable without a running stack.
public enum RankingEngine {
    /// Which two items to compare next while inserting a new item.
    public struct Comparison: Equatable, Sendable {
        public let candidate: ItemID
        public let opponent: ItemID
    }

    public typealias ItemID = UUID

    /// State of an in-progress insertion. Binary search over the existing list:
    /// each answer halves the remaining range, so a shelf of fifteen resolves in
    /// four questions and a shelf of three in two.
    public struct Insertion: Equatable, Sendable {
        public let candidate: ItemID
        /// The ordered list the candidate is being placed into.
        public let list: [ItemID]
        /// Inclusive bounds of where the candidate could still land.
        public private(set) var low: Int
        public private(set) var high: Int
        public private(set) var comparisonsMade: Int

        /// Four is the cap: past that, the questions stop feeling like play and
        /// start feeling like data entry. A longer list settles over later
        /// sessions instead.
        public static let maxComparisons = 4

        public init(candidate: ItemID, list: [ItemID]) {
            self.candidate = candidate
            self.list = list
            low = 0
            high = list.count
            comparisonsMade = 0
        }

        /// The item to face off against, or nil when the position is settled.
        public var nextComparison: Comparison? {
            guard low < high, comparisonsMade < Insertion.maxComparisons else { return nil }
            return Comparison(candidate: candidate, opponent: list[midpoint])
        }

        var midpoint: Int {
            (low + high) / 2
        }

        /// `candidateWon` means "I reach for the new one first".
        public mutating func record(candidateWon: Bool) {
            guard low < high else { return }
            let mid = midpoint
            if candidateWon {
                high = mid
            } else {
                low = mid + 1
            }
            comparisonsMade += 1
        }

        /// A skip resolves the current step without expressing a preference:
        /// the candidate settles at the midpoint rather than pushing either way.
        public mutating func skip() {
            guard low < high else { return }
            let mid = midpoint
            low = mid
            high = mid
            comparisonsMade += 1
        }

        /// Where the candidate lands: `low` once the range collapses, and the
        /// unresolved midpoint if the cap was hit first.
        public var resolvedIndex: Int {
            low < high ? midpoint : low
        }

        public var isSettled: Bool {
            nextComparison == nil
        }

        /// The list with the candidate placed.
        public func result() -> [ItemID] {
            var next = list
            next.insert(candidate, at: min(resolvedIndex, next.count))
            return next
        }
    }

    /// Applies a later comparison to an already-ordered list.
    ///
    /// A contradiction is resolved by the smallest move that satisfies it —
    /// lifting the winner to just above the loser — rather than re-sorting.
    /// Re-sorting would let one late answer reshuffle a list the user built
    /// deliberately over weeks.
    public static func applying(
        winner: ItemID,
        over loser: ItemID,
        to list: [ItemID]
    ) -> [ItemID] {
        guard let winnerIndex = list.firstIndex(of: winner),
              let loserIndex = list.firstIndex(of: loser),
              winnerIndex > loserIndex
        else { return list }

        var next = list
        next.remove(at: winnerIndex)
        next.insert(winner, at: loserIndex)
        return next
    }
}
