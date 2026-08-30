import DataKit
import DesignSystem
import SwiftUI

/// Rung 4 and its confirmation: the form, then the personal-scope promise.
///
/// Built to `G.AddLadder` rung 3 and its `created` state. One stated
/// divergence: the frame's "add a photo" button is not rendered — `core/Media`
/// does not exist yet (GLO-16 PR 1, upload blocked on GLO-48's R2), and a
/// button that silently does nothing is worse than an absent one. It returns
/// with the capture pipeline.
public struct CreateRungView: View {
    @State private var model: CreateRungModel
    @State private var brandSearchTask: Task<Void, Never>?
    private let onBack: () -> Void
    private let onDone: () -> Void

    public init(model: CreateRungModel, onBack: @escaping () -> Void = {}, onDone: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.onBack = onBack
        self.onDone = onDone
    }

    public var body: some View {
        LadderScaffold(ladder: model.ladder, onBack: onBack) {
            if let confirmed = model.confirmedMeta {
                confirmation(confirmed)
            } else {
                form
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .task { await model.loadCategories() }
        .onChange(of: model.brandQuery) { _, _ in scheduleBrandSearch() }
        .animation(Tokens.Motion.pop(Tokens.Motion.med), value: model.confirmedMeta == nil)
    }

    // MARK: - The form

    @ViewBuilder private var form: some View {
        Text("CREATE IT · 4 FIELDS, NO REVIEW QUEUE")
            .eyebrow(color: Tokens.Semantic.accentText)

        VStack(alignment: .leading, spacing: 0) {
            GlossedInput("rare beauty", text: $model.brandQuery, label: "brand", hint: brandHint)
                .plainTyping()
            brandMatches
        }

        GlossedInput("soft pinch liquid blush", text: $model.productName, label: "product")
            .plainTyping()
        GlossedInput("joy · 2.5ml mini", text: $model.variantText, label: "variant")
            .plainTyping()
        // The select reads the model rather than holding its own copy — a
        // pick made anywhere (including a picker state's pre-fill) shows,
        // and the displayed label can never disagree with the draft.
        GlossedSelect(
            options: model.categories.map(\.label),
            selection: Binding(
                get: { model.pickedCategory?.label ?? "" },
                set: { label in
                    if let category = model.categories.first(where: { $0.label == label }) {
                        model.pick(category: category)
                    }
                }
            ),
            label: "category"
        )

        Button("create + add to shelf") {
            Task { await model.create() }
        }
        .buttonStyle(.glossed(block: true))
        .disabled(!model.canCreate)

        if let failure = model.failure {
            Text(failure.userMessage).meta()
        }
    }

    /// A brand must come from the catalog — the draft carries an id, not a
    /// string — so typing shows the brands that exist and picking one fills
    /// the field. No match means the brand itself is missing, which is a
    /// different gap than this rung closes (brands are reference data).
    @ViewBuilder private var brandMatches: some View {
        if model.pickedBrand == nil, !model.brandOptions.isEmpty {
            VStack(spacing: 6) {
                ForEach(model.brandOptions) { brand in
                    Button {
                        model.pick(brand: brand)
                    } label: {
                        Text(brand.name)
                            .font(Typography.control(Typography.Size.body, weight: .semibold))
                            .foregroundStyle(Tokens.Ink.primary)
                            .padding(.horizontal, Tokens.Space.s4)
                            .frame(minHeight: 38)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Tokens.Ground.card)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                                    .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
    }

    private var brandHint: String? {
        guard model.pickedBrand == nil, !model.brandQuery.isEmpty, model.brandOptions.isEmpty else { return nil }
        return "pick a brand from the list — no free-text brands"
    }

    // MARK: - The confirmation

    /// The frame's `created` state: the card, the deal, the way back.
    @ViewBuilder private func confirmation(_ meta: CreateRungModel.ConfirmedMeta) -> some View {
        Text("ADDED · PERSONAL SCOPE")
            .eyebrow(color: Tokens.Semantic.accentText)

        ProductCard(
            meta: .init(brand: meta.brand, name: meta.name, variant: meta.variant),
            isPersonalScope: true
        ) {
            ProductMock(
                kind: ProductMock.Kind.usual(forCategory: model.pickedCategory?.slug ?? ""),
                tint: ProductMock.tint(for: meta.name),
                scale: 52
            )
        }

        Text(
            "it lives on your shelf and in your rankings. it stays out of everyone else's counts "
                + "until three people log the same product — that's what the badge means."
        )
        .font(Typography.mono(11))
        .lineSpacing(4)
        .foregroundStyle(Tokens.Ink.soft)
        .padding(.init(top: 11, leading: 12, bottom: 11, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Support.lilacSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
        )

        Button("back to your shelf", action: onDone)
            .buttonStyle(.glossed(.secondary, block: true))
    }

    /// One in-flight lookup at a time, debounced like the search rung's.
    private func scheduleBrandSearch() {
        brandSearchTask?.cancel()
        brandSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.searchBrands()
        }
    }
}
