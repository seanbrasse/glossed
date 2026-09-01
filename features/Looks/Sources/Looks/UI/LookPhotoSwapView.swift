import DesignSystem
import PhotosUI
import SwiftUI

/// One look photo, opened (Sean, Aug 31 evening — the same ruling as the
/// pfp): "clicking on it should open the photo up and then allow the user
/// to swap it with a new photo from their gallery or take a picture on the
/// spot and swap. This is how the looks should work too."
///
/// The swap keeps the SLOT: same photo row, same position, same tags —
/// 0054's write moves only the bytes. The dots may sit oddly on a very
/// different shot; re-pinning them is the edit screen's job, and the list
/// under the post still names every product either way.
public struct LookPhotoSwapView: View {
    private let media: LookMedia
    /// The whole pipeline behind one verb: prepare, presign this look's
    /// namespace at this photo's position, PUT, swap the row's key.
    private let swap: @Sendable (Data) async throws -> Void
    private let onSwapped: () -> Void
    private let onClose: () -> Void

    @State private var pickingLibrary = false
    @State private var picked: PhotosPickerItem?
    @State private var takingPhoto = false
    @State private var uploading = false
    @State private var failure: String?

    public init(
        media: LookMedia,
        swap: @escaping @Sendable (Data) async throws -> Void,
        onSwapped: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.media = media
        self.swap = swap
        self.onSwapped = onSwapped
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            HStack(spacing: Tokens.Space.s3) {
                Text("photo \(media.position + 1)")
                    .font(Typography.display(Typography.Size.h2))
                    .foregroundStyle(Tokens.Ink.primary)
                Spacer(minLength: 0)
                Button("close", action: onClose)
                    .buttonStyle(.glossed(.secondary, size: .sm))
            }
            photo
            Text("swapping keeps this slot — its spot in the carousel and its tags stay.")
                .meta()
            if let failure {
                Text(failure).meta()
            }
            if uploading {
                Text("saving the new photo…").meta()
            }
            Spacer(minLength: 0)
            controls
        }
        .padding(Tokens.Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.Ground.milk)
        .photosPicker(isPresented: $pickingLibrary, selection: $picked, matching: .images)
        .task(id: picked) { await uploadPickedItem() }
        .modifier(LookCameraSheet(isPresented: $takingPhoto) { data in
            takingPhoto = false
            Task { await upload(data) }
        })
    }

    private var photo: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { LookPhotoView(media: media) }
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
                    .allowsHitTesting(false)
            )
    }

    private var controls: some View {
        VStack(spacing: Tokens.Space.s2) {
            Button("swap from your library") { pickingLibrary = true }
                .buttonStyle(.glossed(.primary, block: true))
                .disabled(uploading)
            #if canImport(UIKit)
                if CameraPicker.isAvailable {
                    Button("take a photo") { takingPhoto = true }
                        .buttonStyle(.glossed(.secondary, block: true))
                        .disabled(uploading)
                }
            #endif
        }
    }

    private func uploadPickedItem() async {
        guard let picked else { return }
        guard let data = try? await picked.loadTransferable(type: Data.self) else {
            self.picked = nil
            return
        }
        await upload(data)
        // Cleared LAST, deliberately: this task rides `.task(id: picked)`,
        // so clearing the id first CANCELS the task mid-upload — every
        // in-flight request dies -999 and the failure line lies about the
        // photo. Found on the first live-R2 drive; the composer's picker
        // always cleared at the end for exactly this reason.
        self.picked = nil
    }

    private func upload(_ data: Data) async {
        uploading = true
        failure = nil
        do {
            try await swap(data)
            onSwapped()
        } catch {
            failure = "that swap didn't save — try again."
        }
        uploading = false
    }
}

/// The camera behind a platform check — the macOS test build again.
private struct LookCameraSheet: ViewModifier {
    @Binding var isPresented: Bool
    let onCapture: (Data) -> Void

    func body(content: Content) -> some View {
        #if canImport(UIKit)
            content.fullScreenCover(isPresented: $isPresented) {
                CameraPicker(
                    onCapture: onCapture,
                    onCancel: { isPresented = false }
                )
                .ignoresSafeArea()
            }
        #else
            content
        #endif
    }
}
