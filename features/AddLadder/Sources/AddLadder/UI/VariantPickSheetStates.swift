import DataKit
import DesignSystem
import SwiftUI

// The pick's three states that are not a list — loading, failed, empty —
// moved out of `VariantPickSheet.swift` at the 300-line ceiling when the
// sheet learned to scroll (GLO-108). A mechanical move.

extension VariantPickSheet {
    enum PickState {
        case loading
        case failed(GlossedError)
        case empty
        case options
    }

    var state: PickState {
        if model.isLoading {
            .loading
        } else if let failure = model.failure {
            .failed(failure)
        } else if model.isEmpty {
            .empty
        } else {
            .options
        }
    }

    var loading: some View {
        HStack(spacing: Tokens.Space.s3) {
            ProgressView()
            Text("finding the shades & sizes…").meta()
        }
        .frame(maxWidth: .infinity, minHeight: 88)
    }

    /// A failure is not evidence about the catalog — say it failed and keep
    /// the retry, never an empty state (same rule as the search rung).
    func retry(_ failure: GlossedError) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text(failure.userMessage).meta()
            Button("try again") {
                Task { await model.load() }
            }
            .buttonStyle(.glossed(.secondary, size: .sm))
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    }

    /// A real state: ~a handful of catalog rows have no variants filled in.
    /// The way onward is the rung behind this sheet — its "none of these"
    /// still stands — so the sheet only has to say why it cannot proceed.
    var empty: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("no shades or sizes on file for this one yet — scanning the barcode adds yours exactly.")
                .meta()
            Button("back") { onCancel() }
                .buttonStyle(.glossed(.secondary, size: .sm))
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    }

    // Up to six rows sit inline and the sheet stays compact. More than six
    // scroll inside a capped viewport that ends on a half row — the cut row
    // is the scroll affordance. Without the cap a 40-shade foundation grew
    // the sheet past the screen and took the header, the close and the
    // confirm with it: a pick that could be started but never finished
    // (GLO-88). Numbers are workshop-able; the shape is not optional.
    // Internal rather than private, and paired with `scrolls(variantCount:)`
    // below, because GLO-88's fix was enforced by two constants that nothing
    // asserted (GLO-168). A shape described only in a comment is a shape one
    // edit away from being gone.
}
