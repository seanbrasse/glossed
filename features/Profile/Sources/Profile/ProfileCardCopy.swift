import DataKit
import Foundation

/// The words the profile's cards wear. Lifted out of `ProfileTabsModel` when
/// the fourth tab took that file to SwiftLint's 300-line ceiling (GLO-261) —
/// a move, with one addition (`photosLine`) for the looks grid.
///
/// Every line here counts YOUR OWN things. None of it is a claim about people,
/// so none of it takes an `EvidenceLine`: that primitive is for a claim with a
/// cohort behind it, and borrowing its chrome would dress a count up as
/// evidence.
public enum ProfileCardCopy {
    /// The frame's `mono(r.steps.length + ' steps · ' + r.since)`.
    ///
    /// **`since` diverges, and it has to.** The kit's fixture writes freeform
    /// cadence copy — `started week 3`, `twice a week`, `every 5 days` — and
    /// no column carries any of it. What `routines` does carry is the slot and
    /// `started_on`, so the line states those and stops. Inventing the kit's
    /// phrasing would be a routine describing a schedule nobody set.
    public static func stepsLine(_ routine: MyRoutine) -> String {
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
    static func slotWord(_ slot: RoutineSlot) -> String {
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
    static func sinceWord(_ date: Date?) -> String? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let parts = calendar.dateComponents([.month, .year], from: date)
        guard let month = parts.month, let year = parts.year, months.indices.contains(month - 1) else {
            return nil
        }
        return "\(months[month - 1]) \(year)"
    }

    static let months = [
        "jan", "feb", "mar", "apr", "may", "jun",
        "jul", "aug", "sep", "oct", "nov", "dec"
    ]

    /// The frame's `mono(c.count + ' products')`, singular at one.
    public static func productsLine(_ n: Int) -> String {
        "\(n) \(n == 1 ? "product" : "products")"
    }

    /// One step, named by the thing you own. `brand · product · shade`, and
    /// the shade only when the row has one — a step that prints an empty
    /// separator reads as a missing fact rather than an absent one.
    public static func stepLine(_ step: RoutineStep) -> String {
        [step.brandName, step.productName, step.variantLabel]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// A look tile's chrome: this post's own photos, and whether anyone else
    /// can read it yet.
    ///
    /// `draft` is the word `looks.state` uses, and it is the whole claim — it
    /// says the look is not published, **not** that it is awaiting a review.
    /// Publishing is unmoderated by decision pending GLO-26, and copy that
    /// implied otherwise is the GLO-189 shape exactly.
    public static func lookLine(photoN: Int, isPublished: Bool) -> String {
        let photos = "\(photoN) \(photoN == 1 ? "photo" : "photos")"
        return isPublished ? photos : "\(photos) · draft"
    }
}
