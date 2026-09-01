import DataKit
import DesignSystem
import SwiftUI

// The edit screen's reach and links halves, split from `LookEditView.swift`
// for the 300-line ceiling — the `ComposerTagSection` split, again.

/// WHO SEES IT — the ladder (Sean's ruling, Aug 31 night): draft · only
/// you · friends · public, ONE dial over the two columns underneath.
/// Draft and only-you are both invisible to others; the meaning line under
/// the rungs is what teaches the difference (unfinished vs. kept private).
/// Everything STAGES; nothing writes until the save button.
struct LookEditReachSection: View {
    @Bindable var model: LookEditModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("WHO SEES IT").eyebrow()
            HStack(spacing: Tokens.Space.s2) {
                ForEach(LookEditModel.Reach.allCases, id: \.self) { rung in
                    chip(rung)
                }
            }
            // The current rung, explained — this line carries the draft /
            // only-you distinction the collapsed control would otherwise
            // blur.
            Text(model.reach.meaning).meta()
        }
    }

    private func chip(_ rung: LookEditModel.Reach) -> some View {
        let isOn = model.reach == rung
        return Button(rung.label) {
            model.reach = rung
        }
        .buttonStyle(.plain)
        .font(Typography.mono(12))
        .foregroundStyle(isOn ? Tokens.Ground.card : Tokens.Ink.primary)
        .padding(.vertical, 6)
        .padding(.horizontal, Tokens.Space.s3)
        .background(Capsule().fill(isOn ? Tokens.Ink.primary : Tokens.Ground.card))
        .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityLabel("\(rung.label) — \(rung.meaning)")
    }
}

/// GOES WITH, staged — singular since 0054 and in Sean's evening shapes:
/// the one routine by its label, the one collection in its card form. All
/// of it stages; the diffs reach the tables when the save button writes
/// them (removes before adds — one-per-look means the old link must clear
/// before the new one lands).
struct LookEditLinksSection: View {
    @Bindable var model: LookEditModel
    @State private var offer: LookLinkables?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            if let offer {
                if !offer.routines.isEmpty {
                    RoutineChoiceRow(
                        picks: offer.routines,
                        selection: Binding(
                            get: { model.routines.first?.id },
                            set: { id in
                                model.routines = id.flatMap { picked in
                                    offer.routines.first { $0.id == picked }
                                }.map { [$0] } ?? []
                            }
                        )
                    )
                }
                if !offer.collections.isEmpty {
                    CollectionChoiceRow(
                        picks: offer.collections,
                        selection: Binding(
                            get: { model.collections.first?.id },
                            set: { id in
                                model.collections = id.flatMap { picked in
                                    offer.collections.first { $0.id == picked }
                                }.map { [$0] } ?? []
                            }
                        )
                    )
                }
                if offer.isEmpty {
                    Text("nothing to link yet — make a routine or a collection first.").meta()
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task { offer = await model.loadLinkables() }
    }
}
