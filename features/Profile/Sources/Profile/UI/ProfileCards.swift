import DataKit
import DesignSystem
import SwiftUI

// The four kinds of card the profile's grid draws, and the edit affordance
// they share (GLO-261).

/// One look. **A caption tile, not a photograph**, and the reason is in
/// `ProfileLook`: nothing in this app resolves a `look_photos.r2_key` back to
/// a readable URL, so there is no image to draw. The tile says how many photos
/// the look has and whether it is published, which is true; a tile pointed at
/// a guessed bucket would be a broken image with a caption under it.
///
/// A look post is attributed content, never a claim (GLO-196) — no n, no
/// cohort, no evidence chrome. The only count is this post's own photos.
struct LookTile: View {
    let look: ProfileLook

    var body: some View {
        GlossedCard(padding: Tokens.Space.s3) {
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Spacer(minLength: 0)
                Text(look.caption ?? "no caption")
                    .font(Typography.display(Typography.Size.small))
                    .foregroundStyle(look.caption == nil ? Tokens.Ink.faint : Tokens.Ink.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ProfileCardCopy.lookLine(photoN: look.photoN, isPublished: look.isPublished))
                    .meta()
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .bottomLeading)
        }
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
            }
        }
    }

    private func stepRow(index: Int, step: RoutineStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
            Text("\(index + 1)")
                .font(Typography.display(Typography.Size.small))
                .foregroundStyle(Tokens.Cherry.base)
                .frame(width: 18, alignment: .leading)
            Text(ProfileCardCopy.stepLine(step))
                .font(.system(size: Typography.Size.small))
                .foregroundStyle(Tokens.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
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
