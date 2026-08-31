import DesignSystem
import PhotosUI
import SwiftUI

/// The avatar, and — for the owner with a wired store — the door onto its
/// photo (GLO-272: "an edit icon on the corner of the pfp that lets the
/// user open it and edit the photo"). The `edit profile` button is gone;
/// this corner icon is what replaced its photo half, and the username's
/// half lives in settings.
///
/// Nil store renders the plain seeded avatar — no dead doors. A photo that
/// fails to load, sign, or exist renders the seed too: a pfp is chrome, and
/// the header never breaks over chrome.
struct ProfileAvatarControl: View {
    let name: String
    let store: ProfilePhotoStore?
    /// Owned by the HEADER, not this control: a failure line inside the
    /// avatar's column would widen it and shove the identity sideways —
    /// found on the drive. The parent renders it under the whole row.
    @Binding var failure: String?

    @State private var photoURL: URL?
    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    @State private var uploading = false

    private static let size: CGFloat = 52

    var body: some View {
        avatar
            .overlay(alignment: .bottomTrailing) {
                if store != nil {
                    editBadge
                }
            }
            .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
            .task { await refresh() }
            .task(id: picked) { await uploadPicked() }
    }

    @ViewBuilder private var avatar: some View {
        if let photoURL {
            // The photo, in the avatar's own circle. AsyncImage's failure
            // case falls through to the seed — less, never wrong.
            AsyncImage(url: photoURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Avatar(name: name, size: Self.size)
            }
            .frame(width: Self.size, height: Self.size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair))
            .accessibilityHidden(true)
        } else {
            Avatar(name: name, size: Self.size)
                .accessibilityHidden(true)
        }
    }

    /// The corner icon — the house's own `EditBadge` (a drawn pencil, per
    /// the no-SF-symbols-for-kit-marks rule), riding the avatar's edge. The
    /// glyph is small; the button's contentShape is the badge circle plus
    /// its offset, which is what a thumb actually gets.
    private var editBadge: some View {
        Button {
            picking = true
        } label: {
            EditBadge()
                .opacity(uploading ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(uploading)
        .offset(x: Tokens.Space.s1, y: Tokens.Space.s1)
        .accessibilityLabel("edit your photo")
    }

    private func refresh() async {
        guard let store else { return }
        photoURL = await store.currentURL()
    }

    private func uploadPicked() async {
        guard let store, let picked else { return }
        self.picked = nil
        guard let data = try? await picked.loadTransferable(type: Data.self) else { return }
        uploading = true
        failure = nil
        do {
            try await store.upload(data)
            // Re-sign rather than showing the local bytes: what renders is
            // what the SERVER holds, so a save that silently failed cannot
            // masquerade as a saved photo.
            photoURL = await store.currentURL()
        } catch {
            failure = "that photo didn't save — try again."
        }
        uploading = false
    }
}
