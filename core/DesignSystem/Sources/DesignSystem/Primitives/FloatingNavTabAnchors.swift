import SwiftUI

/// Each tab's horizontal centre in GLOBAL space, keyed by its label.
///
/// Global rather than a named space so a caller drawing in a full-screen
/// overlay — the tour — can use the value without agreeing on a coordinate
/// space with the nav first.
public struct FloatingNavTabAnchors: PreferenceKey {
    public static let defaultValue: [String: CGFloat] = [:]

    public static func reduce(
        value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}
