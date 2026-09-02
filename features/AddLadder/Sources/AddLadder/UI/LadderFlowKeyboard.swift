import SwiftUI

extension LadderFlowView {
    /// SwiftUI has no "resign whatever is focused" — the field's `FocusState`
    /// is `GlossedInput`'s own — so this asks the responder chain directly.
    /// UIKit-only: the package also builds for `swift test` on the Mac. Its
    /// own file because `LadderFlowView.swift` sits at the 300-line ceiling.
    func endEditing() {
        #if canImport(UIKit)
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        #endif
    }
}
