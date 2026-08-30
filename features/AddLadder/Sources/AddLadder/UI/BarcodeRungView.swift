import DesignSystem
import SwiftUI

/// Rung 1: point the camera at the label.
///
/// Built to `G.AddLadder` rung 1 — a centred pop card carrying the barcode
/// graphic, the instruction, and the reason the rung is worth trying, with
/// "none of these" as a peer row underneath.
///
/// The rung the spec pushes as the common path, which is why most of this file
/// is about the cases where the camera is not an option. A phone that cannot
/// scan and a phone you said no to both still have to reach the shelf.
public struct BarcodeRungView: View {
    @State private var model: BarcodeRungModel
    private let onBack: () -> Void

    public init(model: BarcodeRungModel, onBack: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.onBack = onBack
    }

    public var body: some View {
        LadderScaffold(ladder: model.ladder, onBack: onBack) {
            scanCard
            LadderOptionRow(.noneOfThese(prompt: model.escapePrompt)) {
                model.noneOfThese()
            }
        }
        .task {
            let availability = await ScannerPermission.current()
            model.availabilityChanged(to: availability)
        }
    }

    /// The frame's pop card: 2px ink, radius 18, `shadow-md`, `18px 14px`, and
    /// everything inside it centred. The one pop moment this screen is allowed.
    private var scanCard: some View {
        VStack(spacing: 0) {
            surface
            Text(headline)
                .font(Typography.display(18))
                .foregroundStyle(Tokens.Ink.primary)
                .multilineTextAlignment(.center)
                .padding(.top, Tokens.Space.s2)
            if let subhead {
                Text(subhead)
                    .meta()
                    .multilineTextAlignment(.center)
                    .padding(.top, Tokens.Space.s1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, Tokens.Space.s3 + 2)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        )
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.md, y: Tokens.Shadow.md)
        )
    }

    /// The kit draws a barcode here because a static prototype has no camera to
    /// show. In the app the camera *is* the graphic, so it takes the same slot
    /// rather than replacing the card — and when there is no camera the drawing
    /// comes back, which is the state the kit was always showing.
    @ViewBuilder
    private var surface: some View {
        if model.isScanning {
            camera
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin)
                )
                .accessibilityLabel("barcode scanner")
        } else {
            Image(systemName: "barcode")
                .font(Typography.control(40, weight: .medium))
                .foregroundStyle(Tokens.Ink.primary)
                .accessibilityHidden(true)
        }
    }

    /// Never an instruction the phone cannot carry out. #47 shipped "scan the
    /// barcode" to a device with no scanner, which reads as a broken screen
    /// rather than as one of four ways in — so when the camera is not available
    /// the card says what is actually true instead.
    private var headline: String {
        guard model.isScanning else {
            return model.message ?? model.availability.explanation
        }
        return "point at the barcode"
    }

    /// The kit's line is a rationale, not a status, so a status displaces it:
    /// something we just learned about a code the user is holding up is both
    /// more specific and more recent than a reason to be here at all.
    private var subhead: String? {
        guard model.isScanning else { return nil }
        return model.message ?? "a upc match skips the guessing entirely"
    }

    @ViewBuilder
    private var camera: some View {
        #if os(iOS) && !targetEnvironment(macCatalyst)
            BarcodeScannerView { payload in
                Task { await model.scanned(payload) }
            }
        #else
            Color.clear
        #endif
    }
}
