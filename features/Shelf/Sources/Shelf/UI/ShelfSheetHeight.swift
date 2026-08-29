import SwiftUI

/// How tall the item sheet is allowed to be, and how it learns how tall it
/// wants to be (GLO-160).
///
/// The sheet had no bound at all. On `main` it ended *exactly* on the bottom
/// edge of a 16 Pro — measured, not estimated — and it did not scroll, so the
/// next section anyone added pushed `remove from shelf` off the screen while
/// leaving it rendered and hit-testable. GLO-154's per-category chips took a
/// skincare item from three chips to eight and spent the last of the slack.
enum ShelfSheetHeight {
    /// The gap left above a full-height sheet, so it never runs under the
    /// notch and always reads as a sheet in front of the shelf rather than a
    /// screen that replaced it.
    static let topGap: CGFloat = 64

    /// The height to give the sheet: what it wants, until that stops fitting.
    ///
    /// The clamp is the whole fix and it is deliberately one-directional — a
    /// sheet shorter than the space available is left **exactly** as it is,
    /// so every item that fits today looks identical to how it looks today.
    /// Only the sheets that would have overflowed change, and they change
    /// from "unreachable" to "scrollable".
    ///
    /// `content == 0` means the measurement has not arrived on the first
    /// layout pass; falling back to the available height rather than to zero
    /// keeps the sheet from flashing closed before it has been measured.
    static func resolved(content: CGFloat, available: CGFloat) -> CGFloat {
        guard available > 0 else { return content }
        guard content > 0 else { return available }
        return min(content, available)
    }
}

/// Carries the measured content height up out of the scroll view.
///
/// A preference rather than `onGeometryChange`, which is iOS 18 and the floor
/// here is 17.
struct ShelfSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
