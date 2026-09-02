import DataKit
import DesignSystem
import SwiftUI

// The four kinds of card the profile's grid draws, and the edit affordance
// they share (GLO-261).

/// One look — **the photo is the tile.** Sean's Sept 1 direction: no card
/// around it; the first photo fills a square, and the caption, count and
/// status sit under it as plain text. The container is the grid cell.
///
/// A look post is attributed content, never a claim (GLO-196) — no n, no
/// cohort, no evidence chrome. The only count is this post's own photos.
/// A look with no readable photo yet (presign down, or a draft with none)
/// draws a milk square in the photo's place, so the grid keeps its rhythm.
struct LookTile: View {
    let look: ProfileLook

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            photo
            VStack(alignment: .leading, spacing: 2) {
                Text(look.caption ?? "no caption")
                    .font(Typography.display(Typography.Size.small))
                    .foregroundStyle(look.caption == nil ? Tokens.Ink.faint : Tokens.Ink.primary)
                    .lineLimit(1)
                Text(ProfileCardCopy.lookLine(photoN: look.photoN, isPublished: look.isPublished))
                    .meta()
            }
            .padding(.horizontal, Tokens.Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The first photo, square, with the count dots riding its corner. Sized
    /// by the clear base and overlaid (GLO-252's remedy) so a portrait shot
    /// crops instead of growing the tile.
    private var photo: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let url = look.previewURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Tokens.Ground.milk)
                    }
                } else {
                    Rectangle().fill(Tokens.Ground.milk)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
            .overlay(alignment: .bottomTrailing) {
                if look.photoN > 1 {
                    photoDots
                }
            }
    }

    /// One dot per photo, capping out at three (Sean's ruling) — a count
    /// mark, not a pager: the tile does not page, so the dots do not select.
    private static let dotDiameter: CGFloat = 5

    private var photoDots: some View {
        HStack(spacing: Tokens.Space.s1) {
            ForEach(0 ..< min(look.photoN, 3), id: \.self) { _ in
                Circle()
                    .fill(Tokens.Ground.milk)
                    .frame(width: Self.dotDiameter, height: Self.dotDiameter)
            }
        }
        .padding(Tokens.Space.s2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One thing on your shelf, named. The shelf's own cutouts need `imageBase`,
/// which is the app layer's config and not something a feature may guess at
/// (GLO-74), so the tile carries the words.
struct ShelfTile: View {
    let entry: ProfileShelfEntry

    var body: some View {
        GlossedCard(padding: Tokens.Space.s3) {
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Spacer(minLength: 0)
                Text(entry.brandName).eyebrow()
                Text(entry.productName)
                    .font(Typography.display(Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .bottomLeading)
        }
    }
}

/// One routine, as the frame draws it: title beside the mono count, then the
/// steps numbered down the card with the numeral in cherry at width 18.
struct RoutineCard: View {
    let routine: MyRoutine
    /// The collections this routine goes with (0052). Empty draws nothing.
    var links: [LinkedItem] = []
    /// Editing shows each chip's × — nil keeps them inert display.
    var onUnlink: ((UUID) -> Void)?

    var body: some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
                    Text(routine.title)
                        .font(Typography.display(Typography.Size.body))
                        .foregroundStyle(Tokens.Ink.primary)
                    // A count of your OWN steps — not a claim about people, so
                    // it carries no cohort and wears no evidence chrome.
                    Text(ProfileCardCopy.stepsLine(routine)).meta()
                    Spacer(minLength: 0)
                }
                if !routine.steps.isEmpty {
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                            stepRow(index: index, step: step)
                        }
                    }
                }
                if !links.isEmpty {
                    linkRow
                }
            }
        }
    }

    /// "goes with" — the routine's collections (0052), as inert chips, each
    /// wearing an × while the profile is editing. The whole chip is the
    /// remove target then; a 10pt glyph is not one.
    private var linkRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
            Text("goes with").meta()
            ForEach(links) { link in
                Button {
                    onUnlink?(link.id)
                } label: {
                    HStack(spacing: Tokens.Space.s1) {
                        Text(link.title)
                            .font(Typography.mono(11))
                            .foregroundStyle(Tokens.Ink.primary)
                        if onUnlink != nil {
                            Text("×")
                                .font(Typography.mono(11, bold: true))
                                .foregroundStyle(Tokens.Cherry.deep)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, Tokens.Space.s2)
                    .background(Capsule().fill(Tokens.Ground.milk))
                    .overlay(
                        Capsule().strokeBorder(
                            onUnlink != nil ? Tokens.Cherry.deep : Tokens.Ink.faint,
                            lineWidth: Tokens.Border.hair
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(onUnlink == nil)
                .accessibilityLabel(onUnlink != nil ? "unlink \(link.title)" : link.title)
            }
        }
    }

    private func stepRow(index: Int, step: RoutineStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
            Text("\(index + 1)")
                .font(Typography.display(Typography.Size.small))
                .foregroundStyle(Tokens.Cherry.base)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(ProfileCardCopy.stepLine(step))
                    .font(.system(size: Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                // The step's own words (0052), under the product they apply
                // to. Mono and soft — an aside in the owner's voice, not a
                // second product line. Absent entirely when untyped: a
                // reserved empty line would nag every step to have one.
                if let note = step.note, !note.isEmpty {
                    Text(note).meta()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// One collection, as the frame draws it: a tinted card, content pushed to the
/// bottom, title over `mono(N products)`.
///
/// `minHeight:96` and the bottom alignment are the frame's own — they are what
/// makes a two-word title and a six-word one the same object on the page.
struct CollectionCard: View {
    let collection: ProfileCollection

    var body: some View {
        GlossedCard(tint: Self.tint(collection.tint), padding: Tokens.Space.s3) {
            CollectionCardBody(collection: collection)
        }
    }

    /// `collections.cover_tint` is nullable `text` with no check constraint, so
    /// an unrecognised word is a real possibility. It draws untinted rather
    /// than throwing: a cover is decoration, and a cosmetic column should never
    /// be able to take the grid down.
    ///
    /// The four words are the kit's four soft fills and `GlossedCard` already
    /// owns them — nothing here names a colour.
    ///
    /// The return type is spelled through `CollectionCardBody` because
    /// `GlossedCard.Tint` is nested inside a generic, so each specialisation
    /// has its own. That is also why the card's content is a named view rather
    /// than an inline closure.
    static func tint(_ word: String?) -> GlossedCard<CollectionCardBody>.Tint {
        switch word {
        case "butter": .butter
        case "cherry": .cherry
        case "mint": .mint
        case "lilac": .lilac
        default: .plain
        }
    }
}

/// Bottom-aligned, per the frame's `justifyContent:'flex-end'`.
struct CollectionCardBody: View {
    let collection: ProfileCollection

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Spacer(minLength: 0)
            Text(collection.title)
                .font(Typography.display(Typography.Size.body))
                .foregroundStyle(Tokens.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            // A count of your own collection, not a claim about people — no
            // cohort, and no evidence chrome.
            Text(ProfileCardCopy.productsLine(collection.itemN)).meta()
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .bottomLeading)
    }
}
