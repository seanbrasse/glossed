import DesignSystem
import SwiftUI

/// One tag's dot. Sean's "little dots following our design system colors" —
/// so the colors are tokens and nothing here is a literal.
///
/// A dot is a **sticker**, in the app's own language: ink hairline, hard
/// offset shadow, no blur. Cherry when the tag holds something, card ground
/// when it is still empty — an empty dot is a placement in progress, and it
/// should not look like a finished tag.
///
/// **Nothing claim-shaped** (GLO-196): no number rides on a dot. The count
/// lives in the overlay, where it reads as the page indicator it is.
struct LookTagDot: View {
    var isFilled: Bool
    var isSelected = false

    var body: some View {
        Circle()
            .fill(isFilled ? Tokens.Cherry.base : Tokens.Ground.card)
            .frame(width: LookTagGeometry.dotDiameter, height: LookTagGeometry.dotDiameter)
            .overlay(
                Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
            )
            .background(
                Circle()
                    .fill(Tokens.Ink.primary)
                    .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
            )
            .overlay(
                Circle()
                    .strokeBorder(Tokens.Cherry.deep, lineWidth: isSelected ? Tokens.Border.thin : 0)
                    .padding(-4)
            )
            // The dot is drawn small and TAPPED large: the visible mark is
            // 12pt, the touch is the full hit target.
            .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
            .contentShape(Circle())
    }
}

/// The composer's photo, tappable (GLO-266: "you can tap on part of a photo
/// and add a tag").
///
/// No kit frame — `G.Feed` draws a tagged-product list and nothing that
/// creates one — so this is built from the design system under the standing
/// no-frames ruling, for Sean to workshop.
///
/// Generic over the photo it draws so it never holds photo bytes itself: the
/// caller supplies the image, this supplies the tagging. Photos are regulated
/// data (`domain.md` §5) and the fewer places that touch them, the better.
public struct LookTagCanvas<Photo: View>: View {
    @Binding private var board: LookTagBoard
    /// Which spot's picker is open. Nil is "no sheet".
    @State private var editing: UUID?

    private let photoID: UUID
    private let search: LookTagSearch
    private let photo: () -> Photo

    public init(
        board: Binding<LookTagBoard>,
        photoID: UUID,
        search: LookTagSearch,
        @ViewBuilder photo: @escaping () -> Photo
    ) {
        _board = board
        self.photoID = photoID
        self.search = search
        self.photo = photo
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            canvas
            Text("tap the photo to tag what you're wearing.").meta()
        }
        .sheet(item: Binding(get: { editing.map(EditingSpot.init) }, set: { editing = $0?.id })) { open in
            picker(for: open.id)
        }
    }

    /// The gesture lives INSIDE the GeometryReader and reads the proxy
    /// directly, so the tap and the size it is judged against are the same
    /// frame — the first version stored the size from `onAppear` into
    /// `measured` and guarded on it, and a zero captured before layout made
    /// every tap a silent no-op (found driving Sean's Aug 31 screenshot).
    private var canvas: some View {
        photo()
            .overlay {
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { location in
                                tap(at: location, in: proxy.size)
                            }
                        dots(in: proxy.size)
                    }
                }
            }
    }

    private func dots(in size: CGSize) -> some View {
        ForEach(board.spots(on: photoID)) { spot in
            LookTagDot(isFilled: !spot.isEmpty, isSelected: editing == spot.id)
                .position(spot.point.point(in: size))
                .onTapGesture { editing = spot.id }
                .accessibilityLabel(label(for: spot))
        }
    }

    /// A tap either opens a dot or makes one — and **no tap is a dead tap**.
    ///
    /// The three bands, outward from an existing dot: inside the hit radius
    /// it opens that dot. Between the hit radius and the minimum separation,
    /// `place` refuses (two dots that close read as one) — so rather than
    /// doing nothing, that tap opens the dot it was crowding, which is the
    /// tag the user was almost certainly aiming at. Past the separation it
    /// places a new, empty spot and opens its search.
    private func tap(at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if let hit = board.spot(at: location, in: size, on: photoID) {
            editing = hit.id
            return
        }
        let point = TagPoint.of(location, in: size)
        if let placed = board.place(on: photoID, at: point, in: size) {
            editing = placed
            return
        }
        editing = board.spot(
            at: location, in: size, on: photoID,
            radius: LookTagGeometry.minimumSeparation
        )?.id
    }

    @ViewBuilder private func picker(for spotID: UUID) -> some View {
        if let spot = board.spot(spotID) {
            LookTagPicker(
                search: search,
                spot: spot,
                onAdd: { board.add($0.tagged, to: spotID) },
                onRemove: { board.remove($0, from: spotID) },
                onDone: { close() }
            )
            .presentationDetents([.medium, .large])
            .onDisappear { board.discardEmptySpots() }
        }
    }

    /// Closing sweeps a placement the user backed out of — a dot with nothing
    /// behind it is not a tag. Done here AND in `onDisappear` so a swipe-down
    /// dismissal is swept too.
    private func close() {
        editing = nil
        board.discardEmptySpots()
    }

    private func label(for spot: LookTagSpot) -> String {
        guard !spot.isEmpty else { return "an empty tag — tap to search" }
        return "tag: " + spot.products.map(\.label).joined(separator: ", ")
    }
}

/// `sheet(item:)` needs an `Identifiable`; a bare `UUID` is not one.
private struct EditingSpot: Identifiable {
    let id: UUID
}
