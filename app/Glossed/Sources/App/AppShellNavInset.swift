import DesignSystem
import SwiftUI

// GLO-188. The floating nav is an overlay in `AppShell`'s ZStack, so scrolling
// content ends underneath it and every tab loses its last element.

private struct NavInset: ViewModifier {
    /// Scales with text size: the nav grows at accessibility sizes, so a fixed
    /// inset would under-clear it exactly where the occlusion is worst.
    @ScaledMetric(relativeTo: .body) private var navHeight: CGFloat = 88

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
