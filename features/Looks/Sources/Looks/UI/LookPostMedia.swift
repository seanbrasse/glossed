import DesignSystem
import SwiftUI

// The post view's media helpers, split from `LookPostView.swift` when the
// edit door pushed it past the 300-line ceiling — extract, don't accrete.

/// One look photo, whatever its source. The `.unavailable` case is the
/// honest one: the ground plus a mono line, never a spinner at a URL that
/// cannot be built.
struct LookPhotoView: View {
    let media: LookMedia

    var body: some View {
        switch media.kind {
        case let .photo(source):
            switch source {
            case let .data(bytes):
                localImage(bytes)
            case let .remote(url):
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Tokens.Support.lilacSoft
                }
            case .unavailable:
                ZStack {
                    Tokens.Support.lilacSoft
                    Text("photo not available yet").meta()
                }
            }
        }
    }

    @ViewBuilder private func localImage(_ bytes: Data) -> some View {
        #if canImport(UIKit)
            if let image = UIImage(data: bytes) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Tokens.Support.lilacSoft
            }
        #else
            Tokens.Support.lilacSoft
        #endif
    }
}

/// `.page` is iOS-only; the macOS test build compiles this package too, so
/// the style is applied behind a platform check rather than at the call site.
struct PagedTabStyle: ViewModifier {
    let showsIndex: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
            content.tabViewStyle(.page(indexDisplayMode: showsIndex ? .automatic : .never))
        #else
            content
        #endif
    }
}
