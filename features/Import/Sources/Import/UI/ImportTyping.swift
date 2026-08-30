import SwiftUI

// Its own file for the reason this codebase keeps meeting: `ImportView` sits at
// SwiftLint's 300-line ceiling, the same wall `ScreenEntries`, `ShelfModel` and
// `NearMatchRungModelTests` have all hit. Splitting is the established answer.

extension View {
    /// A pasted haul is a list of product names, not prose. Left on the system
    /// default, iOS capitalises the first line and corrects toward English
    /// words — "laneige" becomes "Laneige" with a spell-check underline, and
    /// every line here is matched against the catalog, so a corrected name is
    /// a miss recorded as demand for a product we already stock.
    ///
    /// GLO-57 named this screen as one that would need it, and it did. That
    /// ticket moved the choice into `GlossedInput`, where `.plain` is now the
    /// default — but this editor is a bare `TextEditor`, so the primitive's
    /// default cannot reach it. When the import box becomes a
    /// `GlossedTextArea`, that type wants the same option and this goes away.
    @ViewBuilder
    func plainTyping() -> some View {
        #if canImport(UIKit)
            textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }
}
