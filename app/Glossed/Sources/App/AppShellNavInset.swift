import DesignSystem
import SwiftUI

// GLO-188. The floating nav is an overlay in `AppShell`'s ZStack, so scrolling
// content ends underneath it and every tab loses its last element.

private struct NavInset: ViewModifier {
    /// Fixed, because the nav is fixed: the kit bar (GLO-64) sizes its tabs in
    /// points, not against a text style, so an inset that kept scaling on
    /// caption's curve reserved ~210pt of empty band over a ~66pt bar at the
    /// largest accessibility sizes.
    private let navHeight: CGFloat = 88

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: navHeight)
        }
    }
}

extension View {
    /// Reserves room for the floating nav so a tab's last element stays
    /// reachable. Applied once in the shell rather than per screen — the
    /// occlusion is the shell's, and every tab inherits the fix.
    func clearingFloatingNav() -> some View {
        modifier(NavInset())
    }
}
