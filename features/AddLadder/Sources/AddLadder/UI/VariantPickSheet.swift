import DataKit
import DesignSystem
import SwiftUI

/// The shade/size pick — the logging sheet's front half (GLO-56 → GLO-16).
///
/// No kit frame exists for this screen (checked `screens.jsx` Aug 28: a picked
/// search card is `()=>go(back)`); Sean's ruling is build from the design
/// system in the kit's voice and workshop at review. The voice here is the
/// item sheet's: bottom sheet on a scrim, grabber, mock-led header, sections
/// cut by hairlines, one block button.
///
/// The sheet never logs. Confirming hands the variant id to the rung model —
/// `pickedVariant(_:)` — and the flow host's existing matched-log machinery
/// does the write, spinner, retry and close.
public struct VariantPickSheet: View {
    @State var model: VariantPickModel
    private let onConfirm: (UUID) -> Void
    let onCancel: () -> Void
    /// What the sheet shows below the pick for the chosen variant — the
    /// product's own evidence, handed in by the app because the page that
    /// draws it is another feature (GLO-108). Nil: the sheet ends at the
    /// confirm, as it did.
    private let details: ((CatalogHit, Variant) -> AnyView)?
    /// The sheet's content height, so a short sheet stays short and a tall
    /// one scrolls inside `maxSheetShare` of the screen.
    @State private var contentHeight: CGFloat = 0
    static let maxSheetShare: CGFloat = 0.88

    public init(
        model: VariantPickModel,
        details: ((CatalogHit, Variant) -> AnyView)? = nil,
        onConfirm: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.details = details
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                scrim
                boundedSheet(available: geo.size.height * Self.maxSheetShare)
            }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .task { await model.load() }
    }

    /// The sheet scrolls once it is taller than the screen allows — which
    /// is what the details below the pick are for (Sean, Sep 2: *"we should
    /// be able to scroll the popup when adding a product up to see more
    /// details"*). Until the first measure it takes the room it needs.
    private func boundedSheet(available: CGFloat) -> some View {
        ScrollView {
            sheet
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: PickSheetHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .frame(height: contentHeight > 0 ? min(contentHeight, available) : nil)
        .onPreferenceChange(PickSheetHeightKey.self) { contentHeight = $0 }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var scrim: some View {
        Button(action: onCancel) {
            Tokens.Ink.primary.opacity(0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("close")
    }

    private var sheet: some View {
        GlossedSheet {
            VStack(alignment: .leading, spacing: 0) {
                header
                pickSection
                moreSection
            }
            // Home-indicator clearance on top of the sheet's own padding —
            // same fix as the item sheet, for the same reason.
            .safeAreaPadding(.bottom)
        }
        .compositingGroup()
        .shadow(color: Tokens.Ink.primary.opacity(0.18), radius: 0, x: 0, y: -3)
        .transition(.move(edge: .bottom))
    }

    @Environment(\.catalogImageBase) private var imageBase

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ProductImage(
                catalog: model.hit.catalogImageURL(base: imageBase),
                kind: ProductMock.Kind.usual(forCategory: model.hit.categorySlug),
                tint: ProductMock.tint(for: model.hit.name),
                scale: 58,
                maxWidth: 58,
                rotation: .degrees(-3)
            )
            .frame(width: 58)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.hit.brandName).eyebrow()
                Text(model.hit.name)
                    .font(Typography.display(21))
                    .tracking(-0.42)
                    .foregroundStyle(Tokens.Ink.primary)
                    .padding(.top, 3)
                    .padding(.bottom, 2)
                if let n = model.hit.faceOffCount {
                    EvidenceLine(n: n, label: "face-offs")
                } else {
                    // Nil is unknown, not zero — no line beats a made-up n.
                    Text(model.hit.categorySlug).meta()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            closeButton
        }
    }

    private var closeButton: some View {
        Button(action: onCancel) {
            Text("×")
                .font(Typography.mono(16))
                .foregroundStyle(Tokens.Ink.soft)
                .frame(width: 44, height: 44, alignment: .topTrailing)
        }
        .accessibilityLabel("close")
    }

    private var pickSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Divider()
                .overlay(Tokens.Ground.lineOnCard)
                .padding(.vertical, Tokens.Space.s4)
            // A sole variant is stated, not asked about (`isSole`).
            Text(model.isSole ? "on file" : "which one is yours").eyebrow()
            switch state {
            case .loading:
                loading
            case let .failed(failure):
                retry(failure)
            case .empty:
                empty
            case .options:
                options
                // Only here: a failed or empty pick has no confirmable answer,
                // and a button that cannot ever be pressed is a lie about the
                // state (the picker's own "nothing on file" note says so).
                confirmButton
            }
        }
    }

    /// Below the pick: the product's evidence, the same view its page shows,
    /// behind a hint rather than a full-page button (Sean: *"tell the user
    /// to swipe up for more details"*). A claim needs a subject and the shade
    /// cohort is per variant, so until one is picked the line says so.
    @ViewBuilder private var moreSection: some View {
        if let details, case .options = state {
            Divider()
                .overlay(Tokens.Ground.lineOnCard)
                .padding(.vertical, Tokens.Space.s4)
            Text("swipe up for more ↑").meta()
                .padding(.bottom, Tokens.Space.s3)
            if let variant = model.confirmed {
                details(model.hit, variant)
                    // A different variant is a fresh load, never recycled.
                    .id(variant.id)
            } else {
                Text("pick a shade or size to see how it fits your shade").meta()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static let inlineRowLimit = 6
    static let scrollViewportHeight: CGFloat =
        5.5 * Tokens.hitTarget + 5 * Tokens.Space.s2

    /// Whether the list scrolls inside its cap rather than growing the sheet.
    ///
    /// The load-bearing property is not this boolean but what it implies: past
    /// the limit the sheet's height stops depending on the number of shades,
    /// so the confirm below it cannot be pushed off the screen no matter how
    /// many there are. That is the whole of GLO-88.
    static func scrolls(variantCount: Int) -> Bool {
        variantCount > inlineRowLimit
    }

    @ViewBuilder private var options: some View {
        if model.variants.count > Self.inlineRowLimit {
            ScrollView {
                optionRows
            }
            .frame(height: Self.scrollViewportHeight)
        } else {
            optionRows
        }
        if model.variants.count == 1 {
            Text("the only one on file — it goes on your shelf as this")
                .meta()
                // Wrap, don't truncate (GLO-146). Without this the line
                // rendered as "check it's you…" — the sheet's whole job is
                // getting you to verify the shade before it logs, and the
                // sentence that asks for the check was the one being cut.
                // Same remedy as the remove-confirm line (#131).
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Tokens.Space.s1)
        }
    }

    private var optionRows: some View {
        VStack(spacing: Tokens.Space.s2) {
            ForEach(model.variants) { variant in
                VariantOptionRow(
                    variant: variant,
                    isSelected: variant.id == model.selectedVariantID,
                    marker: model.isSole ? nil : "yours"
                ) {
                    model.select(variant.id)
                }
            }
        }
    }

    private var confirmButton: some View {
        Button("add to shelf") {
            if let confirmed = model.confirmed {
                onConfirm(confirmed.id)
            }
        }
        .buttonStyle(.glossed(block: true))
        .disabled(!model.canConfirm)
        .padding(.top, Tokens.Space.s5)
    }
}

private struct PickSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
