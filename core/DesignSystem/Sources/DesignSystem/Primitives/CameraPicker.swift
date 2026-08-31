#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// The system camera, presented as a sheet — "take a picture on the spot
    /// and swap" (Sean, Aug 31 batch 2). A primitive because two features
    /// need the identical wrapper (the pfp and the look photos) and features
    /// never import features; it knows nothing about what the photo is FOR.
    ///
    /// The caller must gate on `CameraPicker.isAvailable` — offering a
    /// camera button on a device with no camera (every simulator) is a dead
    /// door. `NSCameraUsageDescription` rides `project.yml`.
    public struct CameraPicker: UIViewControllerRepresentable {
        private let onCapture: (Data) -> Void
        private let onCancel: () -> Void

        public init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        public static var isAvailable: Bool {
            UIImagePickerController.isSourceTypeAvailable(.camera)
        }

        public func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        }

        public func updateUIViewController(_: UIImagePickerController, context _: Context) {}

        public func makeCoordinator() -> Coordinator {
            Coordinator(onCapture: onCapture, onCancel: onCancel)
        }

        public final class Coordinator: NSObject {
            private let onCapture: (Data) -> Void
            private let onCancel: () -> Void

            init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
                self.onCapture = onCapture
                self.onCancel = onCancel
            }
        }
    }

    extension CameraPicker.Coordinator: UINavigationControllerDelegate {}

    extension CameraPicker.Coordinator: UIImagePickerControllerDelegate {
        public func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // JPEG at 0.9, matching what the library picker hands the
            // preparers — which re-encode anyway (strip + bound), so this is
            // transport, not the final bytes.
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9)
            else {
                onCancel()
                return
            }
            onCapture(data)
        }

        public func imagePickerControllerDidCancel(_: UIImagePickerController) {
            onCancel()
        }
    }
#endif
