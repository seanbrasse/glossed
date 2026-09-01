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
    /// Internal for the reason `isListingOpen` is: the listing section is this
    /// same type in `LookPostListing.swift`, and `private` is file-scoped.
    @State var state: LookTagViewerState
    @State private var measured: CGSize = .zero
    /// **Collapsed by default** (Sean, Sept 1: "products tagged in the look
    /// should be in an expandable tab"). The photos are the post; the product
    /// list is the receipts, and a look that opens with a wall of names under
    /// it reads as a catalogue entry rather than something someone made.
    ///
    /// Internal, not private: the section itself lives in
    /// `LookPostListing.swift` — the same type across two files, and `private`
    /// is file-scoped.
    @State var isListingOpen = false
    private let caption: String?
    private let media: [LookMedia]
    private let onClose: () -> Void
    /// A product row tapped in the OVERLAY — the door to the product page,
    /// when the host wires one. Nil renders the overlay rows as labels.
    private let onOpenProduct: ((UUID) -> Void)?
    /// What this look links (0050) — already filtered by the both-halves
    /// policy at read time, so everything here is renderable.
    let linkedRoutines: [LinkablePick]
    let linkedCollections: [LinkablePick]
    /// Non-nil for the owner's own look: the chips become editable and the
    /// "+ link" door opens (`LookLinksSection`). Nil renders read-only.
    private let linkEditor: LookLinkEditor?
    /// Non-nil for the owner: the edit button (GLO-272 — "clicking into it
    /// and hitting the edit button"). Nil for anyone else's look.
    private let onEdit: (() -> Void)?
    /// Non-nil for the owner: tapping a photo opens it for the swap (the
    /// evening ruling). Nil renders the photos as they were — untappable.
    private let onOpenPhoto: ((LookMedia) -> Void)?

    public init(
        caption: String?,
        media: [LookMedia],
        board: LookTagBoard,
        linkedRoutines: [LinkablePick] = [],
        linkedCollections: [LinkablePick] = [],
        linkEditor: LookLinkEditor? = nil,
        onClose: @escaping () -> Void,
        onOpenProduct: ((UUID) -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onOpenPhoto: ((LookMedia) -> Void)? = nil
    ) {
        let ordered = media.sorted { $0.position < $1.position }
        self.caption = caption
        self.media = ordered
        self.onClose = onClose
        self.onOpenProduct = onOpenProduct
        self.linkedRoutines = linkedRoutines
        self.linkedCollections = linkedCollections
        self.linkEditor = linkEditor
        self.onEdit = onEdit
        self.onOpenPhoto = onOpenPhoto
        _state = State(initialValue: LookTagViewerState(
            board: board, photoOrder: ordered.map(\.id)
        ))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                HStack(spacing: Tokens.Space.s3) {
                    Button("← back", action: onClose)
                        .buttonStyle(.plain)
                        .font(Typography.mono(12))
                        .foregroundStyle(Tokens.Semantic.accentText)
                        .underline()
                    Spacer(minLength: 0)
                    if let onEdit {
                        Button("edit", action: onEdit)
                            .buttonStyle(GlossedButtonStyle(.secondary, size: .sm))
                    }
                }
                pager
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(Typography.display(Typography.Size.body))
                        .foregroundStyle(Tokens.Ink.primary)
                }
                LookLinksSection(
                    routines: linkedRoutines, collections: linkedCollections, editor: linkEditor
                )
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
            LookPhotoView(media: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    // The owner's door onto the swap. Dots and the toggle sit
                    // ABOVE this in the ZStack, so their taps still win.
                    onOpenPhoto?(item)
                }
            dots(on: item.id)
            if state.hasTags {
                tagToggle
            }
            if let spot = state.openSpot, spot.photoID == item.id {
                spotOverlay(spot)
            }
        }
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

    /// The dot, opened, BESIDE the dot (Sean, Sept 1: "show the products
    /// next to the dot… a small, somewhat translucent card… so you can
    /// literally see what product is being used where on the face"). This
    /// replaced the bottom-anchored card, which answered WHAT but lost the
    /// WHERE.
    ///
    /// A dark translucent scrim (Ink at 72%) with milk text — the pair that
    /// stays legible over any photo, light or busy; the tokens carry both
    /// colors. Flips to whichever side of the dot has room and clamps to the
    /// photo, so it sits beside its dot rather than over it. One spot open
    /// at a time is `LookTagViewerState`'s own rule — both roads here (a dot
    /// tap, the listing's eye) go through it.
    private func spotOverlay(_ spot: LookTagSpot) -> some View {
        let anchor = spot.point.point(in: measured)
        let cardWidth: CGFloat = 190
        let gap: CGFloat = 14
        let inset: CGFloat = Tokens.Space.s2
        // Beside the dot: right of it when the dot sits in the left half,
        // left of it otherwise — then clamped so a corner dot's card stays
        // on the photo.
        let rawX = anchor.x <= measured.width / 2
            ? anchor.x + gap + cardWidth / 2
            : anchor.x - gap - cardWidth / 2
        let minX = cardWidth / 2 + inset
        let maxX = max(measured.width - cardWidth / 2 - inset, minX)
        let estimatedHeight = CGFloat(spot.products.count) * 20 + 2 * Tokens.Space.s2 + 8
        let minY = estimatedHeight / 2 + inset
        let maxY = max(measured.height - estimatedHeight / 2 - inset, minY)
        return VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            ForEach(spot.products) { product in
                if let onOpenProduct {
                    Button(product.label) { onOpenProduct(product.variantID) }
                        .buttonStyle(.plain)
                        .font(Typography.mono(11))
                        .foregroundStyle(Tokens.Ground.milk)
                        .underline()
                        .multilineTextAlignment(.leading)
                } else {
                    Text(product.label)
                        .font(Typography.mono(11))
                        .foregroundStyle(Tokens.Ground.milk)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(Tokens.Space.s2)
        .frame(width: cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                .fill(Tokens.Ink.primary.opacity(0.72))
        )
        .position(
            x: min(max(rawX, minX), maxX),
            y: min(max(anchor.y, minY), maxY)
        )
        .transition(.opacity)
    }

    // MARK: - the list under the photos

    // "under each photo will be a list of tagged products, ordered by
    // category" — and the eye beside a row reveals its dot, crossing photos
    // when it must (`reveal` is that whole sentence in one call).
}
