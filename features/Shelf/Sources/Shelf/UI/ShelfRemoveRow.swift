import DesignSystem
import SwiftUI

/// The way off the shelf (GLO-72, remove half), moved whole from the sheet
/// when GLO-87's icons pushed the file past its length. Quiet on purpose —
/// the kit's one pop moment on the sheet is "rank it", and removal should
/// feel deliberate, not prominent. Status lives in the tried icons now.
///
/// Two taps to remove, both in place: the row arms, then confirms. A native
/// dialog would leave the design system's voice for the one action that
/// most needs to feel deliberate.
struct ShelfRemoveRow: View {
    let isRemoving: Bool
    /// The failed remove's user message, owned by the model — a failure
    /// outlives any one render of this row.
    let failure: String?
    let onRemove: () -> Void

    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRemoving {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("removing…").meta()
                }
            } else if let failure {
                Text(failure).meta()
                Button("try again") { onRemove() }
                    .buttonStyle(.glossed(.secondary, size: .sm))
            } else if isConfirming {
                Text("off your bays and counts — your face-offs stay in the log.")
                    .meta()
                    // Without this the line truncates instead of wrapping —
                    // the sheet's animation pass proposes it one line.
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("yes, remove") { onRemove() }
                        .buttonStyle(.glossed(.ink, size: .sm))
                    Button("keep it") { isConfirming = false }
                        .buttonStyle(.glossed(.secondary, size: .sm))
                }
            } else {
                Button {
                    isConfirming = true
                } label: {
                    Text("remove from shelf")
                        .font(Typography.mono(12))
                        .foregroundStyle(Tokens.Cherry.deep)
                        .underline()
                        .frame(minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("remove from shelf")
            }
        }
        .padding(.top, 12)
    }
}
