import DataKit
import DesignSystem
import SwiftUI

/// `G.Tune` — sharpen your matches: skin type, concerns, and the brands
/// you rate, none of which ever gated the payoff. Chips toggle freely;
/// save is one write and the door back to discover.
public struct TuneView: View {
    @State private var model: TuneModel
    /// Brand options come from whoever opens the screen (the kit's list is
    /// a fixture; the app can supply the catalog's top brands).
    private let brandOptions: [String]
    private let onBack: () -> Void
    private let onSaved: () -> Void

    public init(
        model: TuneModel,
        brandOptions: [String],
        onBack: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.brandOptions = brandOptions
        self.onBack = onBack
        self.onSaved = onSaved
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button("← back", action: onBack)
                    .buttonStyle(.plain)
                    .font(Typography.mono(12))
                    .foregroundStyle(Tokens.Semantic.accentText)
                    .underline()
                Text("AFTER SIGNUP · NEVER BEFORE THE PAYOFF")
                    .eyebrow(color: Tokens.Semantic.accentText)
                Text("sharpen your\nmatches")
                    .font(Typography.display(28))
                    .tracking(-0.56)
                    .foregroundStyle(Tokens.Ink.primary)
                Text("three taps, and none of it gated the payoff")
                    .handAside()
                    .rotationEffect(.degrees(-1))
                Text("SKIN TYPE").eyebrow()
                Segmented(
                    options: SkinType.allCases.map(\.rawValue),
                    selection: Binding(
                        get: { model.selection.skinType?.rawValue ?? "" },
                        set: { model.selection.skinType = SkinType(rawValue: $0) }
                    )
                )
                Text("CONCERNS").eyebrow()
                ChipGroup(TuneModel.concernOptions.map { concern in
                    Chip(
                        concern,
                        kind: .attribute,
                        selected: model.selection.concerns.contains(concern),
                        action: { model.toggleConcern(concern) }
                    )
                })
                Text("BRANDS YOU RATE").eyebrow()
                ChipGroup(brandOptions.map { brand in
                    Chip(
                        brand,
                        kind: .attribute,
                        selected: model.selection.brands.contains(brand),
                        action: { model.toggleBrand(brand) }
                    )
                })
                if let error = model.saveError {
                    Text(error.userMessage).meta()
                }
                Button(model.phase == .saving ? "saving…" : "save") {
                    model.saveSelection(onSaved: onSaved)
                }
                .buttonStyle(.glossed(block: true))
                .disabled(model.phase == .loading || model.phase == .saving)
                .padding(.top, Tokens.Space.s1)
                Text("looks and swatches used to live here too — both moved to phase 1.5")
                    .meta()
                    .frame(maxWidth: .infinity)
            }
            .padding(.init(top: 14, leading: 16, bottom: 110, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Ground.milk)
        .task { model.loadCurrent() }
    }
}
