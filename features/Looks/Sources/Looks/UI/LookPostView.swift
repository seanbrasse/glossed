import DesignSystem
import SwiftUI

/// A look, opened — the post view (GLO-266).
///
/// **No kit frame**: `screens.jsx` holds no look-post screen (the Aug 31
/// sweep's finding 01), so this is built from the design system under the
/// standing no-frames ruling, for Sean to workshop in the PR.
///
/// The behavior is not workshopped, though — it is Sean's spec, held by
/// `LookTagViewerState` where every sentence is an assertion: tags hidden
/// until the bottom-left toggle, one dot open at a time, the list under the
/// photos ordered by category, and a listed product tagged on another photo
/// scrolling there before its dot opens.
///
/// **A look post is attributed content, never a claim** (GLO-196): no n, no
/// `EvidenceLine`, and the only count anywhere is "N photos" chrome.
public struct LookPostView: View {
    @State private var state: LookTagViewerState
    @State private var measured: CGSize = .zero
    private let caption: String?
    private let media: [LookMedia]
    private let onClose: () -> Void
    /// A product row tapped in the OVERLAY — the door to the product page,
    /// when the host wires one. Nil renders the overlay rows as labels.
    private let onOpenProduct: ((UUID) -> Void)?

    public init(
        caption: String?,
        media: [LookMedia],
        board: LookTagBoard,
        onClose: @escaping () -> Void,
        onOpenProduct: ((UUID) -> Void)? = nil
    ) {
        let ordered = media.sorted { $0.position < $1.position }
        self.caption = caption
        self.media = ordered
        self.onClose = onClose
        self.onOpenProduct = onOpenProduct
        _state = State(initialValue: LookTagViewerState(
            board: board, photoOrder: ordered.map(\.id)
        ))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Button("← back", action: onClose)
                    .buttonStyle(.plain)
                    .font(Typography.mono(12))
                    .foregroundStyle(Tokens.Semantic.accentText)
                    .underline()
                pager
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(Typography.display(Typography.Size.body))
                        .foregroundStyle(Tokens.Ink.primary)
                }
                listing
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
    }

    // MARK: - the photos

    /// Full-width and squared, the composer's own rule: a normalized tag has
    /// to mean the same thing at every size, and a container whose aspect
    /// ratio changes with the image would move every dot on it.
    private var pager: some View {
        TabView(selection: Binding(
            get: { state.showingIndex },
            set: { state.show(index: $0) }
        )) {
            ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                page(item).tag(index)
            }
        }
        .modifier(PagedTabStyle(showsIndex: media.count > 1))
        .aspectRatio(1, contentMode: .fit)
        .background(
            GeometryReader { proxy in
                Color.clear.onAppear { measured = proxy.size }
                    .onChange(of: proxy.size) { _, size in measured = size }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        // Decoration must not eat the card's touches: a Shape overlay
        // hit-tests as its filled bounds, which is the entire card — found by
        // driving it (the toggle never fired through the border).
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
                .allowsHitTesting(false)
        )
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.md, y: Tokens.Shadow.md)
        )
    }

    private func page(_ item: LookMedia) -> some View {
        ZStack(alignment: .bottomLeading) {
            photo(item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            dots(on: item.id)
            if state.hasTags {
                tagToggle
            }
            if let spot = state.openSpot, spot.photoID == item.id {
                spotOverlay(spot)
            }
        }
    }

    @ViewBuilder private func photo(_ item: LookMedia) -> some View {
        switch item.kind {
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
                // The ground plus one honest mono line — the photo's bytes
                // have no read path yet, and its tags still work.
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

    // MARK: - the tags

    /// Sean: "Tags only show in the photo when the user clicks on the tag
    /// icon in the bottom left." `visibleSpots` is already empty when the
    /// toggle is off — the state enforces the rule; this only draws it.
    private func dots(on photoID: UUID) -> some View {
        ForEach(state.visibleSpots.filter { $0.photoID == photoID }) { spot in
            LookTagDot(isFilled: true, isSelected: state.openSpot?.id == spot.id)
                .position(spot.point.point(in: measured))
                .onTapGesture {
                    withAnimation(Tokens.Motion.pop(Tokens.Motion.fast)) {
                        if state.openSpot?.id == spot.id {
                            state.closeSpot()
                        } else {
                            state.open(spotID: spot.id)
                        }
                    }
                }
        }
    }

    private var tagToggle: some View {
        Button {
            withAnimation(Tokens.Motion.pop(Tokens.Motion.fast)) {
                state.toggleTags()
            }
        } label: {
            TagIcon(size: 18)
                .foregroundStyle(state.isRevealingTags ? Tokens.Ground.card : Tokens.Ink.primary)
                .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                .background(
                    Circle().fill(state.isRevealingTags ? Tokens.Cherry.base : Tokens.Ground.card)
                )
                .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair))
        }
        .buttonStyle(.plain)
        .padding(Tokens.Space.s3)
        .accessibilityLabel(state.isRevealingTags ? "hide tags" : "show tags")
    }

    /// The dot, opened: "a small overlay in the photo view. We can click on
    /// products in the overlay." Anchored to the photo's bottom rather than
    /// floated at the dot — a card clamped inside a small photo ends up
    /// covering its own dot more often than beside it.
    private func spotOverlay(_ spot: LookTagSpot) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            ForEach(spot.products) { product in
                if let onOpenProduct {
                    Button(product.label) { onOpenProduct(product.variantID) }
                        .buttonStyle(.plain)
                        .font(Typography.display(Typography.Size.small))
                        .foregroundStyle(Tokens.Ink.primary)
                        .underline()
                } else {
                    Text(product.label)
                        .font(Typography.display(Typography.Size.small))
                        .foregroundStyle(Tokens.Ink.primary)
                }
            }
        }
        .padding(Tokens.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.md).fill(Tokens.Ground.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
        )
        .padding(Tokens.Space.s3)
        .padding(.leading, Tokens.hitTarget)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - the list under the photos

    /// "under each photo will be a list of tagged products, ordered by
    /// category" — and the eye beside a row reveals its dot, crossing photos
    /// when it must (`reveal` is that whole sentence in one call).
    @ViewBuilder private var listing: some View {
        if state.hasTags {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text("TAGGED IN THIS LOOK").eyebrow()
                ForEach(state.listing) { group in
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        Text(group.category.label).meta()
                        ForEach(group.entries) { entry in
                            listingRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func listingRow(_ entry: LookTagListingEntry) -> some View {
        Button {
            withAnimation(Tokens.Motion.pop(Tokens.Motion.med)) {
                _ = state.reveal(entry.product.variantID)
            }
        } label: {
            HStack(spacing: Tokens.Space.s2) {
                Text(entry.product.label)
                    .font(Typography.display(Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.primary)
                Spacer(minLength: 0)
                EyeIcon(size: 15)
                    .foregroundStyle(Tokens.Ink.soft)
            }
            .padding(.vertical, Tokens.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.product.label) — show its tag on the photo")
    }
}

/// `.page` is iOS-only; the macOS test build compiles this package too, so
/// the style is applied behind a platform check rather than at the call site.
private struct PagedTabStyle: ViewModifier {
    let showsIndex: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
            content.tabViewStyle(.page(indexDisplayMode: showsIndex ? .automatic : .never))
        #else
            content
        #endif
    }
}
