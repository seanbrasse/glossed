import DesignSystem
import SwiftUI

// The claim-sheet presenter, split from `OwnProfileView.swift` — the pfp
// control left that file over the 300-line ceiling (caught locally after the
// chrome PR merged; extracting is the house remedy).

extension View {
    /// Presents the handle claim from the profile itself when the seam is
    /// wired, so the profile can reload when it closes (GLO-239).
    @ViewBuilder
    func claimSheet(
        isPresented: Binding<Bool>, store: HandleStore?, onDismiss: @escaping () -> Void
    ) -> some View {
        if let store {
            sheet(isPresented: isPresented, onDismiss: onDismiss) {
                HandleClaimView(store: store)
            }
        } else {
            self
        }
    }
}
