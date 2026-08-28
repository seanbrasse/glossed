import DesignSystem
import SwiftUI

/// Rung 2: point the camera at the label.
///
/// The rung the spec pushes as the common path, which is why most of this file
/// is about the cases where the camera is not an option. A phone that cannot
/// scan and a phone you said no to both still have to reach the shelf.
public struct BarcodeRungView: View {
    @State private var model: BarcodeRungModel

    public init(model: BarcodeRungModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s5) {
            RungRail(trail: model.ladder.trail, current: model.ladder.rung)
            viewfinder
            // Only while the camera is live: when it is not, the card below is
            // already saying this, and saying it twice reads as a stutter.
            if model.isScanning, let message = model.message {
                Text(message).meta()
            }
            LadderOptionRow(.noneOfThese(prompt: model.escapePrompt)) {
                model.noneOfThese()
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.Ground.milk)
        .task {
            let availability = await ScannerPermission.current()
            model.availabilityChanged(to: availability)
        }
    }

    @ViewBuilder
    private var viewfinder: some View {
        if model.isScanning {
            camera
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
                )
                .accessibilityLabel("barcode scanner")
        } else {
            // Not an error state and not styled as one: the camera is one way
            // in of four, and the row below is a working way forward. It also
            // must not say "scan the barcode" to a phone that cannot — an
            // instruction the user cannot follow reads as a broken screen.
            GlossedCard(tint: .butter) {
                Text(model.message ?? "scan the barcode")
                    .font(Typography.display(20))
                    .foregroundStyle(Tokens.Ink.primary)
            }
        }
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
