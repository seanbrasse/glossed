import DataKit
import DesignSystem
import SwiftUI

/// `G.Profile`'s lower half: the segmented control and the tab it selects
/// (GLO-230). Built to the frame at `screens.jsx` 52995–62773, pulled as
/// source this session.
///
/// The frame draws the control `alignSelf:'flex-start'` — it hugs its two
/// words rather than spanning the column, which `fixedSize` reproduces on a
/// `Segmented` whose segments otherwise split the width evenly.
struct ProfileTabsSection: View {
    @Bindable var model: ProfileTabsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if model.tabs.count > 1 {
                HStack {
                    Segmented(options: model.tabs.map(\.label), selection: selection)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                }
            }
            content
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: { model.tab.label },
            set: { model.tab = ProfileTab(rawValue: $0) ?? .routines }
        )
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .routines: routines
        case .collections: EmptyView()
        }
    }

    @ViewBuilder private var routines: some View {
        if model.isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if model.routines.isEmpty {
            emptyRoutines
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                ForEach(model.routines) { RoutineCard(routine: $0) }
            }
        }
    }

    /// Never blank, the empty-state rule the shelf already follows: it says
    /// what a routine is and where routines are made. It does not offer to
    /// make one — the composer lives behind the + drawer and this feature
    /// cannot reach it.
    private var emptyRoutines: some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text("no routines yet")
                    .font(Typography.display(Typography.Size.h3))
                    .foregroundStyle(Tokens.Ink.primary)
                Text("a routine is the order you use things in. build one from the + button.")
                    .meta()
            }
        }
    }
}

/// One routine, as the frame draws it: title beside the mono count, then the
/// steps numbered down the card with the numeral in cherry at width 18.
struct RoutineCard: View {
    let routine: MyRoutine

    var body: some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
                    Text(routine.title)
                        .font(Typography.display(Typography.Size.body))
                        .foregroundStyle(Tokens.Ink.primary)
                    // A count of your OWN steps — not a claim about people, so
                    // it carries no cohort and wears no evidence chrome.
                    Text(ProfileTabsModel.stepsLine(routine)).meta()
                    Spacer(minLength: 0)
                }
                if !routine.steps.isEmpty {
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                            stepRow(index: index, step: step)
                        }
                    }
                }
            }
        }
    }

    private func stepRow(index: Int, step: RoutineStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
            Text("\(index + 1)")
                .font(Typography.display(Typography.Size.small))
                .foregroundStyle(Tokens.Cherry.base)
                .frame(width: 18, alignment: .leading)
            Text(ProfileTabsModel.stepLine(step))
                .font(.system(size: Typography.Size.small))
                .foregroundStyle(Tokens.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
