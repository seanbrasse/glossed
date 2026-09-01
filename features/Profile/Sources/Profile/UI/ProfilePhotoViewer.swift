import DesignSystem
import PhotosUI
import SwiftUI

/// The pfp, opened (Sean, Aug 31 evening): "clicking on it should open the
/// photo up and then allow the user to swap it with a new photo from their
/// gallery or take a picture on the spot and swap."
///
/// The photo large, and under it the two swap doors — the library always,
/// the camera only where one exists (`CameraPicker.isAvailable`; a
/// simulator never shows a dead camera button). A swap uploads, then
/// re-signs and renders what the SERVER holds, so a silently failed save
/// cannot masquerade as a saved photo.
struct ProfilePhotoViewer: View {
    let name: String
    let store: ProfilePhotoStore
    /// The URL the avatar already held — shown instantly; the fresh sign
    /// replaces it after a swap.
    @Binding var photoURL: URL?
    let onClose: () -> Void

    @State private var pickingLibrary = false
    @State private var picked: PhotosPickerItem?
    @State private var takingPhoto = false
    @State private var uploading = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            HStack(spacing: Tokens.Space.s3) {
                Text("your photo")
                    .font(Typography.display(Typography.Size.h2))
                    .foregroundStyle(Tokens.Ink.primary)
                Spacer(minLength: 0)
                Button("close", action: onClose)
                    .buttonStyle(.glossed(.secondary, size: .sm))
            }
            photo
            if let failure {
                Text(failure).meta()
            }
            if uploading {
                Text("saving your photo…").meta()
            }
            Spacer(minLength: 0)
            controls
        }
        .padding(Tokens.Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.Ground.milk)
        .photosPicker(isPresented: $pickingLibrary, selection: $picked, matching: .images)
        .task(id: picked) { await uploadPickedItem() }
        .modifier(CameraSheet(isPresented: $takingPhoto) { data in
            takingPhoto = false
            Task { await upload(data) }
        })
    }

    /// The photo, big and squared — the container proposes the square
    /// (GLO-252's remedy), the seed stands in when there is no photo or it
    /// fails to load.
    private var photo: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let photoURL {
                    AsyncImage(url: photoURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Avatar(name: name, size: 120)
                    }
                } else {
                    ZStack {
                        Rectangle().fill(Tokens.Support.lilacSoft)
                        VStack(spacing: Tokens.Space.s3) {
                            Avatar(name: name, size: 120)
                            Text("no photo yet — you're the initial.").meta()
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
                    .allowsHitTesting(false)
            )
    }

    private var controls: some View {
        VStack(spacing: Tokens.Space.s2) {
            Button("choose from your library") { pickingLibrary = true }
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
        self.picked = nil
        guard let data = try? await picked.loadTransferable(type: Data.self) else { return }
        await upload(data)
    }

    private func upload(_ data: Data) async {
        uploading = true
        failure = nil
        do {
            try await store.upload(data)
            photoURL = await store.currentURL()
        } catch {
            failure = "that photo didn't save — try again."
        }
        uploading = false
    }
}

/// The camera, behind a platform check — macOS compiles this package for
/// tests and has neither UIKit nor a camera sheet.
private struct CameraSheet: ViewModifier {
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
