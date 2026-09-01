import DesignSystem
import SwiftUI

// The composer's link section (0050 → 0054), split from `ComposerView` for
// the 300-line ceiling — `ComposerTagSection`'s reason and its neighbor.

extension ComposerView {
    /// Singular since 0054, and SEPARATE since Sean's evening note ("these
    /// should be separate or there should be an indicator of what's a
    /// routine and what's a collection"): one routine by its label, one
    /// collection in its card form. Absent entirely when there is nothing
    /// to offer.
    @ViewBuilder var linkSection: some View {
        if !model.linkables.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                if !model.linkables.routines.isEmpty {
                    RoutineChoiceRow(
                        picks: model.linkables.routines,
                        selection: Binding(
                            get: { model.linkedRoutineIDs.first },
                            set: { model.linkedRoutineIDs = $0.map { [$0] } ?? [] }
                        )
                    )
                }
                if !model.linkables.collections.isEmpty {
                    CollectionChoiceRow(
                        picks: model.linkables.collections,
                        selection: Binding(
                            get: { model.linkedCollectionIDs.first },
                            set: { model.linkedCollectionIDs = $0.map { [$0] } ?? [] }
                        )
                    )
                }
                Text("a link shows only where both sides are visible.").meta()
            }
        }
    }
}
