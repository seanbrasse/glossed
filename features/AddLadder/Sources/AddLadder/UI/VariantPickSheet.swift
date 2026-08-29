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
    @State private var model: VariantPickModel
    private let onConfirm: (UUID) -> Void
    private let onCancel: () -> Void

    public init(
        model: VariantPickModel,
        onConfirm: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            scrim
            sheet
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .task { await model.load() }
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
            Text("which one is yours").eyebrow()
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

    private enum PickState {
        case loading
        case failed(GlossedError)
        case empty
        case options
    }

    private var state: PickState {
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

    private var loading: some View {
        HStack(spacing: Tokens.Space.s3) {
            ProgressView()
            Text("finding the shades & sizes…").meta()
        }
        .frame(maxWidth: .infinity, minHeight: 88)
    }

    /// A failure is not evidence about the catalog — say it failed and keep
    /// the retry, never an empty state (same rule as the search rung).
    private func retry(_ failure: GlossedError) -> some View {
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
    private var empty: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("no shades or sizes on file for this one yet — scanning the barcode adds yours exactly.")
                .meta()
            Button("back") { onCancel() }
                .buttonStyle(.glossed(.secondary, size: .sm))
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    }

    /// Up to six rows sit inline and the sheet stays compact. More than six
    /// scroll inside a capped viewport that ends on a half row — the cut row
    /// is the scroll affordance. Without the cap a 40-shade foundation grew
    /// the sheet past the screen and took the header, the close and the
    /// confirm with it: a pick that could be started but never finished
    /// (GLO-88). Numbers are workshop-able; the shape is not optional.
    private static let inlineRowLimit = 6
    private static let scrollViewportHeight: CGFloat =
        5.5 * Tokens.hitTarget + 5 * Tokens.Space.s2

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
            Text("the only one we have on file — check it's yours")
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
                    isSelected: variant.id == model.selectedVariantID
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
