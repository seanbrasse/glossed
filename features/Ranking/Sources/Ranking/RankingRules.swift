import Foundation

/// When a category may be ranked, and which of its items are eligible.
///
/// These are the rules that decide whether ranking feels like a reward or a
/// chore, so they live in one place rather than being re-derived per screen.
public enum RankingRules {
    /// Ranking unlocks at three items. Below that a shelf is a list, not an
    /// ordering — asking someone to rank two things tells us almost nothing and
    /// makes the app feel demanding early.
    public static let defaultUnlockMinimum = 3

    /// An item is eligible once its wear-in window has elapsed.
    ///
    /// Skin cell turnover runs about 28 days, so judging a moisturizer at day
    /// three is judging nothing. Categories carry their own window: sunscreen
    /// and cleanser are immediate, actives take weeks, retinoids longer.
    public static func isPastWearIn(
        startedOn: Date?,
        wearInDays: Int,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        guard wearInDays > 0 else { return true }
        // No start date on a category that needs one means we cannot vouch for
        // the window having passed, so it stays out of face-offs.
        guard let startedOn else { return false }
        let start = calendar.startOfDay(for: startedOn)
        let today = calendar.startOfDay(for: now)
        guard let elapsed = calendar.dateComponents([.day], from: start, to: today).day else { return false }
        return elapsed >= wearInDays
    }

    /// Days left before an item can be ranked — drives the "week N" label and
    /// the nudge when the window closes.
    public static func daysUntilRankable(
        startedOn: Date?,
        wearInDays: Int,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Int? {
        guard wearInDays > 0, let startedOn else { return wearInDays > 0 ? nil : 0 }
        let start = calendar.startOfDay(for: startedOn)
        let today = calendar.startOfDay(for: now)
        guard let elapsed = calendar.dateComponents([.day], from: start, to: today).day else { return nil }
        return max(0, wearInDays - elapsed)
    }

    /// Whether a category's list can be ranked at all.
    public static func isUnlocked(eligibleItemCount: Int, minimum: Int = defaultUnlockMinimum) -> Bool {
        eligibleItemCount >= minimum
    }

    /// Percentile of a position in a list, 1.0 for #1 down to 0.0 for last.
    ///
    /// A single-item list contributes nothing: being the only blush you own is
    /// not evidence that it is a good blush, and letting it score 1.0 would let
    /// one-item shelves dominate every leaderboard.
    public static func percentile(position: Int, listLength: Int) -> Double? {
        guard listLength > 1, position >= 1, position <= listLength else { return nil }
        return 1.0 - Double(position - 1) / Double(listLength - 1)
    }
}
