import DataKit
import DesignSystem
import SwiftUI

/// Other people's routines. GLO-128, `docs/tech/02` §4.
public struct RoutinesBrowseView: View {
    @State private var model: RoutinesBrowseModel
    @State private var opened: BrowseRoutine?
    private let store: RoutinesStore

    public init(store: RoutinesStore) {
        _model = State(wrappedValue: RoutinesBrowseModel(store: store))
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                header
                slots
                if model.isLoading {
                    ProgressView().padding(.top, Tokens.Space.s8)
                } else if model.isEmpty {
                    Text(model.emptyLine)
                        .font(.system(size: Typography.Size.small))
                        .foregroundStyle(Tokens.Ink.soft)
                } else {
                    ForEach(model.rows) { row in
                        Button { opened = row } label: { RoutineCard(row: row) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await model.load() }
        .sheet(item: $opened) { row in
            RoutineDetailView(store: store, routineID: row.routineID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("ROUTINES").eyebrow()
            Text("how other people do it")
                .font(Typography.display(Typography.Size.h1))
                .foregroundStyle(Tokens.Ink.primary)
            Text(model.filterLine)
                .font(.system(size: Typography.Size.small))
                .foregroundStyle(Tokens.Ink.soft)
        }
    }

    private var slots: some View {
        Segmented(
            options: RoutineSlot.allCases.map(\.label),
            selection: Binding(
                get: { model.slot.label },
                set: { label in
                    guard let slot = RoutineSlot.allCases.first(where: { $0.label == label }),
                          slot != model.slot else { return }
                    Task { await model.setSlot(slot) }
                }
            )
        )
    }
}

struct RoutineCard: View {
    let row: BrowseRoutine

    var body: some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text(row.title)
                    .font(.system(size: Typography.Size.h3, weight: .semibold))
                    .foregroundStyle(Tokens.Ink.primary)
                Text("@\(row.ownerHandle)")
                    .font(.system(size: Typography.Size.meta))
                    .foregroundStyle(Tokens.Ink.soft)
                HStack(spacing: Tokens.Space.s4) {
                    EvidenceLine(n: row.stepN, label: "steps")
                    EvidenceLine(n: row.ownerShelfN, label: "on their shelf")
                }
            }
        }
    }
}

/// Someone else's routine, in order.
public struct RoutineDetailView: View {
    @State private var model: RoutineDetailModel

    public init(store: RoutinesStore, routineID: UUID) {
        _model = State(wrappedValue: RoutineDetailModel(store: store, routineID: routineID))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                if model.isLoading {
                    ProgressView().padding(.top, Tokens.Space.s8)
                } else if model.isUnavailable {
                    Text("not here")
                        .font(Typography.display(Typography.Size.h2))
                        .foregroundStyle(Tokens.Ink.primary)
                } else if let detail = model.detail {
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        Text(detail.slot.label.uppercased()).eyebrow()
                        Text(detail.title)
                            .font(Typography.display(Typography.Size.h1))
                            .foregroundStyle(Tokens.Ink.primary)
                        EvidenceLine(n: model.stepCount, label: "steps")
                    }
                    ForEach(detail.steps) { step in
                        stepRow(step)
                    }
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await model.load() }
    }

    private func stepRow(_ step: RoutineStep) -> some View {
        GlossedCard {
            HStack(alignment: .top, spacing: Tokens.Space.s3) {
                Text("\(step.position)")
                    .font(Typography.mono(Typography.Size.h3, bold: true))
                    .foregroundStyle(Tokens.Ink.faint)
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text(step.brandName)
                        .font(.system(size: Typography.Size.meta))
                        .foregroundStyle(Tokens.Ink.soft)
                    Text(step.productName)
                        .font(.system(size: Typography.Size.body, weight: .semibold))
                        .foregroundStyle(Tokens.Ink.primary)
                    if let label = step.variantLabel {
                        Text(label)
                            .font(Typography.mono(Typography.Size.meta))
                            .foregroundStyle(Tokens.Ink.soft)
                    }
                }
            }
        }
    }
}
