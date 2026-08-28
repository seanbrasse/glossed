import DataKit
import DesignSystem
import SwiftUI

/// The sheet's chips + note section (GLO-16): the fixed experience vocabulary
/// as selectable chips, and the owner's own words under them.
///
/// Built to the kit's item-sheet voice — a hairline-cut section like the fit
/// block above it. The kit's sheet *shows* chips; the selectable state reuses
/// `Chip`'s own `selected`/`action`, so applied and pickable chips are one
/// component in one voice, not a picker pretending to be a display.
struct ShelfChipsSection: View {
    @Bindable var model: ShelfChipsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            header
            if model.isLoading {
                HStack(spacing: Tokens.Space.s3) {
                    ProgressView()
                    Text("finding the chips…").meta()
                }
            } else if !model.vocabulary.isEmpty {
                chips
            }
            if model.needsStartDate {
                // The skincare week rule, said out loud instead of a silent
                // refusal: the toggle did nothing and this is why.
                Text("set a start date first — week 1 and week 10 are opposite facts")
                    .meta(color: Tokens.Cherry.deep)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GlossedTextArea(text: $model.note, label: "your note", minHeight: 56)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Tokens.Ground.line).frame(height: 1.5)
        }
        .padding(.top, 14)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("how it's going").eyebrow()
            if let week = model.currentWeek {
                Text("week \(week)").meta()
            }
        }
    }

    private var chips: some View {
        ChipGroup(model.vocabulary.enumerated().map { index, chip in
            Chip(
                chip.label,
                kind: chip.valence == .like ? .like : .dislike,
                size: .sm,
                week: model.appliedIDs.contains(chip.id) ? model.currentWeek : nil,
                rotation: .degrees([-1, 1.2][index % 2]),
                selected: model.appliedIDs.contains(chip.id),
                action: { model.toggle(chip.id) }
            )
        })
    }
}
