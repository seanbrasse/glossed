import DesignSystem
import SwiftUI

/// The search bar a tag opens with (GLO-266: "starting a tag opens up a
/// search bar"), and the list of what is already in this spot — because a
/// spot holds SEVERAL products, so the picker cannot dismiss on the first
/// pick the way a one-shot chooser would.
///
/// No kit frame: `G.Feed` draws the tagged-product *list* and nothing that
/// creates one. Built from the design system per the standing no-frames
/// ruling, for Sean to workshop.
///
/// **Nothing here is claim-shaped** (GLO-196). There is no n, no
/// `EvidenceLine`, and "on your shelf" is a section the results sit in, never
/// a badge on a product — a tag attributes, it does not rate.
public struct LookTagPicker: View {
    @State private var model: LookTagSearchModel
    private let spot: LookTagSpot
    private let onAdd: (TagSearchResult) -> Void
    private let onRemove: (UUID) -> Void
    private let onDone: () -> Void

    public init(
        search: LookTagSearch,
        spot: LookTagSpot,
        onAdd: @escaping (TagSearchResult) -> Void,
        onRemove: @escaping (UUID) -> Void,
        onDone: @escaping () -> Void
    ) {
        _model = State(initialValue: LookTagSearchModel(search))
        self.spot = spot
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onDone = onDone
    }

    public var body: some View {
        GlossedSheet {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                header
                GlossedInput(
                    "what are you wearing?",
                    text: $model.query,
                    hint: model.scope.line
                )
                if !spot.products.isEmpty {
                    inThisSpot
                }
                resultsList
                Button("done") { onDone() }
                    .buttonStyle(.glossed(block: true))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("tag a product")
                .font(Typography.display(22))
                .foregroundStyle(Tokens.Ink.primary)
            Spacer(minLength: 0)
            // Mono because it is a count, and it counts THIS spot — a page
            // indicator, not a sample size.
            if let line = spot.countLine {
                Text(line)
                    .font(Typography.mono(11))
                    .foregroundStyle(Tokens.Ink.soft)
            }
        }
    }

    /// What this one spot already holds. Sean's "tags can hold several
    /// products each" is only true if the picker shows the several.
    private var inThisSpot: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("IN THIS TAG").eyebrow()
            ForEach(spot.products) { product in
                HStack {
                    Text(product.label)
                        .font(Typography.display(14, weight: 700))
                        .foregroundStyle(Tokens.Ink.primary)
                    Spacer(minLength: 0)
                    Button("untag") { onRemove(product.variantID) }
                        .buttonStyle(.plain)
                        .font(Typography.mono(11))
                        .foregroundStyle(Tokens.Cherry.deep)
                }
            }
        }
    }

    @ViewBuilder private var resultsList: some View {
        if let failure = model.failure {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text(failure).meta()
                Button("try again") { model.query += " " }
                    .buttonStyle(.glossed(.secondary, size: .sm))
            }
        } else {
            switch model.vacancy {
            case .tooShort:
                Text("type at least \(LookTagSearchModel.minimumQuery) letters.").meta()
            case .nothingFound:
                // Never a dead end: the miss says what was searched, so the
                // scope is never a silent reason for an empty list.
                Text("nothing matched — \(model.scope.line).").meta()
            case .none:
                sections
            }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            ForEach(Array(model.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    if model.scope.isSectioned {
                        Text(section.isShelf ? "ON YOUR SHELF" : "IN THE CATALOG").eyebrow()
                    }
                    ForEach(section.results) { result in
                        resultRow(result)
                    }
                }
            }
        }
    }

    private func resultRow(_ result: TagSearchResult) -> some View {
        let held = spot.holds(result.variantID)
        return Button {
            if !held {
                onAdd(result)
            }
        } label: {
            HStack(spacing: Tokens.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.label)
                        .font(Typography.display(14, weight: 700))
                        .foregroundStyle(Tokens.Ink.primary)
                    Text(result.category.label).meta()
                }
                Spacer(minLength: 0)
                Text(held ? "tagged" : "tag")
                    .font(Typography.mono(11))
                    .foregroundStyle(held ? Tokens.Ink.faint : Tokens.Cherry.deep)
            }
            .frame(minHeight: Tokens.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(held)
        .accessibilityLabel(held ? "\(result.label), already tagged" : "tag \(result.label)")
    }
}
