import DataKit
import DesignSystem
import Looks
import SwiftUI

// The post half of GLO-254's door, split from `AppShellLooks.swift` when the
// read path landed (GLO-272) pushed that file past the 300-line ceiling —
// the house remedy is to extract rather than accrete. The composer host
// stays; the post host and its crossing live here.

/// The look the profile opened (GLO-266). A wrapper because a bare UUID is
/// not `Identifiable`, and the shell's covers key on identity.
struct OpenLook: Identifiable {
    let id: UUID
}

/// Loads one of YOUR looks and shows it as a post.
///
/// The app owns this crossing for AppShellProductPage's reason: the tile is
/// `features/Profile`'s, the post view is `features/Looks`', and features
/// never import features.
///
/// **Labels come from the shelf.** `MyLook.spots` carries variant ids and
/// nothing else — the schema's shape — and Sean's scope ruling means every
/// taggable product IS a shelf row, so the shelf read resolves them. A tag
/// whose product has since left the shelf still renders, in an honest
/// bucket, rather than vanishing from a photo it is pinned to.
struct LookPostHost: View {
    let client: GlossedClient
    let lookID: UUID
    let onClose: () -> Void

    /// What the post view needs, loaded. A named type because the house
    /// linter is right about three-member tuples: this one crosses an await.
    struct LoadedPost {
        let caption: String?
        let visibility: PrivacyScope
        let isPosted: Bool
        let media: [LookMedia]
        let board: LookTagBoard
        let linkedRoutines: [LinkablePick]
        let linkedCollections: [LinkablePick]
    }

    @State private var post: LoadedPost?
    @State private var failed = false
    @State private var editing = false

    var body: some View {
        Group {
            if let post {
                LookPostView(
                    caption: post.caption, media: post.media, board: post.board,
                    linkedRoutines: post.linkedRoutines,
                    linkedCollections: post.linkedCollections,
                    // The live link chips retired when the edit screen landed
                    // (GLO-272's uniform ruling: edits go through the edit
                    // button and stage behind save) — so no linkEditor, and
                    // the chips render read-only.
                    onClose: onClose,
                    // `mine()` is what loaded this post, so the viewer IS the
                    // owner — the edit door is unconditional here, and becomes
                    // conditional the day a stranger's look renders.
                    onEdit: { editing = true }
                )
                .fullScreenCover(isPresented: $editing) {
                    editScreen(for: post)
                }
            } else if failed {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Button("← back", action: onClose)
                        .buttonStyle(.plain)
                        .font(Typography.mono(12))
                        .foregroundStyle(Tokens.Semantic.accentText)
                        .underline()
                    Text("that look didn't load — try again.").meta()
                }
                .padding(Tokens.Space.s5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Tokens.Ground.milk)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tokens.Ground.milk)
            }
        }
        .task { await load() }
    }

    /// The edit screen (GLO-272), staged over the loaded post. Fresh model
    /// per presentation — the cover's identity rule, `lookTrip`'s reasoning.
    private func editScreen(for post: LoadedPost) -> some View {
        LookEditView(
            model: LookEditModel(
                baseline: LookEditModel.Baseline(
                    caption: post.caption, visibility: post.visibility,
                    isPosted: post.isPosted, board: post.board,
                    routines: post.linkedRoutines, collections: post.linkedCollections
                ),
                store: editStore
            ),
            media: post.media,
            search: .overShelf(ShelfRepository(client: client)),
            onDone: {
                editing = false
                // Reload in place so the post shows what was saved — the
                // cover under the cover must not go on rendering the old
                // caption over the new row.
                self.post = nil
                Task { await load() }
            },
            onDeleted: {
                editing = false
                onClose()
            }
        )
    }

    /// One closure per repository write — the model decides which of these a
    /// save needs (diff-only, LookEditModel's contract).
    private var editStore: LookEditStore {
        let looks = LooksRepository(client: client)
        let links = LinksRepository(client: client)
        let routines = RoutinesRepository(client: client)
        let collections = CollectionsRepository(client: client)
        let lookID = lookID
        let photoIDs = (post?.media ?? []).map(\.id)
        return LookEditStore(
            updateCaption: { try await looks.updateCaption(lookID: lookID, to: $0) },
            setVisibility: { try await looks.setVisibility(lookID: lookID, to: $0) },
            setPosted: { posted in
                if posted {
                    try await looks.publish(lookID: lookID)
                } else {
                    try await looks.unpost(lookID: lookID)
                }
            },
            replaceSpots: { board in
                try await looks.replaceSpots(
                    photoIDs: photoIDs,
                    with: board.spots.map { spot in
                        LookDraft.Spot(
                            id: spot.id, photoID: spot.photoID,
                            x: spot.point.x, y: spot.point.y,
                            products: spot.products.enumerated().map { index, product in
                                LookDraft.SpotProduct(variantID: product.variantID, position: index)
                            }
                        )
                    }
                )
            },
            setLinks: { changes in
                if !changes.addRoutineIDs.isEmpty || !changes.addCollectionIDs.isEmpty {
                    try await links.link(
                        lookID: lookID,
                        routineIDs: changes.addRoutineIDs,
                        collectionIDs: changes.addCollectionIDs
                    )
                }
                for id in changes.removeRoutineIDs {
                    try await links.unlink(lookID: lookID, routineID: id)
                }
                for id in changes.removeCollectionIDs {
                    try await links.unlink(lookID: lookID, collectionID: id)
                }
            },
            linkables: {
                async let mine = routines.mine()
                async let theirs = collections.mine()
                return try await LookLinkables(
                    routines: mine.map { LinkablePick(id: $0.routineID, title: $0.title) },
                    collections: theirs.map { LinkablePick(id: $0.collectionID, title: $0.title) }
                )
            },
            delete: { try await looks.delete(lookID: lookID) }
        )
    }

    private func load() async {
        do {
            let looks = try await LooksRepository(client: client).mine()
            guard let look = looks.first(where: { $0.lookID == lookID }) else {
                failed = true
                return
            }
            let rows = await (try? ShelfRepository(client: client).shelf()) ?? []
            let byVariant = Dictionary(rows.map { ($0.variantID, $0) }) { first, _ in first }
            // The read path (GLO-272): one batched presign for the whole
            // carousel. A photo the resolver could not sign renders
            // `.unavailable` — named on the page, never a spinner at a URL
            // that cannot be built.
            let urls = await LookPhotoURLResolver(client: client)
                .resolve(look.photos.map(\.photoID))
            let media = look.photos.map { photo in
                LookMedia(
                    id: photo.photoID, position: photo.position,
                    kind: .photo(urls[photo.photoID].map { .remote($0) } ?? .unavailable)
                )
            }
            let spots = look.spots.map { spot in
                LookTagSpot(
                    id: spot.tagID, photoID: spot.photoID,
                    point: TagPoint(x: spot.x, y: spot.y),
                    products: spot.products.map { product in
                        if let row = byVariant[product.variantID] {
                            TaggedProduct(
                                variantID: product.variantID,
                                label: [row.brandName, row.productName].joined(separator: " ")
                                    + (row.variantLabel.map { " · \($0)" } ?? ""),
                                category: TagCategory(slug: row.categorySlug, label: row.categoryLabel)
                            )
                        } else {
                            // Off the shelf since it was tagged. An honest
                            // bucket beats a dot that lost its contents.
                            TaggedProduct(
                                variantID: product.variantID,
                                label: "a product no longer on your shelf",
                                category: TagCategory(slug: "", label: "no longer on your shelf")
                            )
                        }
                    }
                )
            }
            // What the look GOES WITH (0050) — read through the both-halves
            // policy, so nothing arrives that should not render. A failed
            // links read degrades to none rather than failing the post.
            let links = await (try? LinksRepository(client: client).links(lookID: lookID))
                ?? LookLinks(routines: [], collections: [])
            post = LoadedPost(
                caption: look.caption, visibility: look.visibility,
                isPosted: look.isPublished,
                media: media, board: LookTagBoard(spots),
                linkedRoutines: links.routines.map { LinkablePick(id: $0.id, title: $0.title) },
                linkedCollections: links.collections.map { LinkablePick(id: $0.id, title: $0.title) }
            )
        } catch {
            failed = true
        }
    }
}

extension AppShell {
    /// The cover the profile's look tile opens (GLO-266).
    @ViewBuilder func lookPost(_ open: OpenLook) -> some View {
        if let client = session.client {
            LookPostHost(client: client, lookID: open.id, onClose: { openLook = nil })
        }
    }
}
