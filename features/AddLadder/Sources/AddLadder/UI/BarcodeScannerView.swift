#if os(iOS) && !targetEnvironment(macCatalyst)
    import SwiftUI
    import Vision
    import VisionKit

    /// The camera, wrapped. Owns no decisions — it reads payloads off labels and
    /// hands them up; whether one is a match, a miss or a misread is
    /// `BarcodeRungModel`'s call.
    struct BarcodeScannerView: UIViewControllerRepresentable {
        /// Retail product codes only. Leaving this at the default would also
        /// recognise QR codes on the packaging, which are marketing URLs — the
        /// rung would reject them as misreads, but only after telling the user
        /// to hold steadier at something that was never a product code.
        static let symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .itf14, .code128]

        let onScan: (String) -> Void

        func makeUIViewController(context: Context) -> DataScannerViewController {
            let scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: BarcodeScannerView.symbologies)],
                qualityLevel: .balanced,
                // One label at a time. A shelf of products in frame is a menu
                // nobody asked for, and picking from it is the near-match rung.
                recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: false,
                isGuidanceEnabled: true,
                isHighlightingEnabled: true
            )
            context.coordinator.start(scanner, onScan: onScan)
            return scanner
        }

        func updateUIViewController(_: DataScannerViewController, context _: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        /// Stops the camera when the rung goes away. Without this the session
        /// keeps running behind the next screen, which is both a battery cost
        /// and a green dot the user cannot explain.
        static func dismantleUIViewController(
            _ scanner: DataScannerViewController,
            coordinator: Coordinator
        ) {
            coordinator.stop()
            scanner.stopScanning()
        }

        @MainActor
        final class Coordinator {
            private var reading: Task<Void, Never>?

            func start(_ scanner: DataScannerViewController, onScan: @escaping (String) -> Void) {
                try? scanner.startScanning()
                reading = Task { [weak scanner] in
                    guard let scanner else { return }
                    for await items in scanner.recognizedItems {
                        for case let .barcode(barcode) in items {
                            guard let payload = barcode.payloadStringValue else { continue }
                            onScan(payload)
                        }
                    }
                }
            }

            func stop() {
                reading?.cancel()
                reading = nil
            }

            deinit { reading?.cancel() }
        }
    }
#endif
