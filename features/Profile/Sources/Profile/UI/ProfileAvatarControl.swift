import DesignSystem
import PhotosUI
import SwiftUI

/// The avatar, and — for the owner with a wired store — the door onto its
/// photo. Reworked to Sean's evening ruling: TAPPING THE AVATAR opens the
/// photo up (`ProfilePhotoViewer`), and the swap — library or camera —
/// happens there; the corner badge stays as the affordance that says the
/// door exists. The username's editor lives in settings.
///
/// Nil store renders the plain seeded avatar — no dead doors. A photo that
/// fails to load, sign, or exist renders the seed too: a pfp is chrome, and
/// the header never breaks over chrome.
struct ProfileAvatarControl: View {
    let name: String
    let store: ProfilePhotoStore?
    @State private var photoURL: URL?
    @State private var viewing = false

    private static let size: CGFloat = 52

    var body: some View {
        Group {
            if let store {
                Button {
                    viewing = true
                } label: {
                    avatar
                        .overlay(alignment: .bottomTrailing) { editBadge }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("your photo — open and edit")
                .modifier(PhotoViewerCover(isPresented: $viewing) {
                    ProfilePhotoViewer(
                        name: name, store: store, photoURL: $photoURL,
                        onClose: { viewing = false }
                    )
                })
            } else {
                avatar
            }
        }
        .task { await refresh() }
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

    /// The corner badge — a STICKER now (EditBadge's own doctrine): the
    /// whole avatar is the button, and the badge only says the door exists.
    private var editBadge: some View {
        EditBadge()
            .offset(x: Tokens.Space.s1, y: Tokens.Space.s1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func refresh() async {
        guard let store else { return }
        photoURL = await store.currentURL()
    }
}

/// `fullScreenCover` is iOS-only; the macOS test build compiles this package
/// too — the `EditCover` trade, made for the pfp.
private struct PhotoViewerCover<Cover: View>: ViewModifier {
    let isPresented: Binding<Bool>
    @ViewBuilder let cover: () -> Cover

    func body(content: Content) -> some View {
        #if os(iOS)
            content.fullScreenCover(isPresented: isPresented, content: cover)
        #else
            content.sheet(isPresented: isPresented, content: cover)
        #endif
    }
}
