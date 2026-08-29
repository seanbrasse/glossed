import DataKit
import DesignSystem
import SwiftUI

/// The sheet's status control (GLO-72): the full `item_status` enum as one
/// single-select `Segmented`, in the lifecycle area above remove.
///
/// No kit frame exists for any lifecycle UI (checked `G.Shelf` — zero
/// occurrences); built per the no-frames ruling, workshop at review. The
/// row scrolls sideways for the same reason the domain filter does: four
/// lowercase words do not fit a narrow phone, and a control cut at the
/// margin looks broken rather than continuing.
struct ShelfStatusRow: View {
    let status: ItemStatus
    let onChange: (ItemStatus) -> Void

    private static let order: [ItemStatus] = [.wantToTry, .own, .finished, .repurchased]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("status").meta()
            ScrollView(.horizontal, showsIndicators: false) {
                Segmented(
                    options: ShelfStatusRow.order.map(ShelfItem.label(for:)),
                    selection: Binding(
                        get: { ShelfItem.label(for: status) },
                        set: { picked in
                            if let match = ShelfStatusRow.order.first(
                                where: { ShelfItem.label(for: $0) == picked }
                            ) {
                                onChange(match)
                            }
                        }
                    )
                )
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 12)
    }
}
