import DataKit
import DesignSystem
import Looks
import Media
import PhotosUI
import SwiftUI

// GLO-254's door. Its own file for the reason `AppShellDrawer` and
// `AppShellPrivacy` are: `AppShell.swift` sits at SwiftLint's 300-line ceiling,
// and the house remedy is to extract rather than accrete.

/// The look composer, wired to the real pipeline and hosted by the app.
///
/// **Why the app owns this rather than a feature.** `features/Looks` builds the
/// composer and `LooksStore.live` is its own; what it cannot do is reach the
/// photo library, because that is a picker the shell presents, and it cannot be
/// opened from `features/Discover` either — features never import features. The
/// app layer composes, so the crossing lives here, exactly as GLO-151's product
/// page and GLO-211's cold-start picks do.
///
/// **The photo picker is not optional.** `ComposerView` draws its add tile only
/// when it is handed an `onPickPhoto`, and `canPost` needs a photo — so a door
/// opened without a picker is the "room with no floor" the drawer's own notes
/// warn about. `PhotosPicker` is the SDK's out-of-process picker: no new
/// dependency, and no library-access prompt to declare, because it grants none.
struct LookComposerHost: View {
    @State private var model: ComposerModel
    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    private let onSaved: () -> Void
    private let onClose: () -> Void

    private let search: LookTagSearch

    init(client: GlossedClient, onSaved: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onSaved = onSaved
        self.onClose = onClose
        search = .overShelf(ShelfRepository(client: client))
        _model = State(initialValue: ComposerModel(store: .live(
            client: client,
            // **Chosen visibly, which is what `AlwaysAllowedChecker` asks for
            // by refusing to be a default.** `SensitiveContentChecking` has no
            // live conformance anywhere in the repo — the framework needs an
            // entitlement and does not exist on the simulator (GLO-198's seam).
            // So the on-device screen tech/03 §1 names is NOT running here.
            // What bounds it today: this composer saves a DRAFT. Nothing in the
            // app publishes one and no surface shows one to anyone, so an
            // unscreened photo reaches the owner's own account and stops there.
            // A real checker is a launch requirement before that stops being
            // true — it belongs with GLO-26's moderation stack, not with this
            // door.
            preparer: PhotoPreparer(checker: AlwaysAllowedChecker())
        )))
    }

    var body: some View {
        ComposerView(
            model: model,
            onPickPhoto: { picking = true },
            search: search,
            onSaved: { _ in onSaved() },
            onClose: onClose
        )
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
        // Keyed on the selection so a second pick re-runs it; the load is
        // cancelled with the sheet rather than outliving it.
        .task(id: picked) { await addPicked() }
    }

    /// A pick that fails to load is dropped in silence on purpose: the strip
    /// shows exactly the photos the composer holds, so a photo that did not
    /// arrive is already visible as its own absence. The failure worth naming
    /// is the save's, and `ComposerView` already names that one.
    private func addPicked() async {
        guard let picked else { return }
        if let data = try? await picked.loadTransferable(type: Data.self) {
            model.addPhoto(data)
        }
        self.picked = nil
    }
}

extension AppShell {
    /// One composer per presentation — `lookTrip`'s reasoning, which is
    /// `ladderTrip`'s and `routineTrip`'s: a full-screen cover keeps its
    /// content's identity across presentations, so without a fresh id a second
    /// `post a look` resumes the first one's caption, photos and minted look
    /// id, and re-uploads into the previous look's R2 namespace.
    @ViewBuilder var lookComposer: some View {
        if let client = session.client {
            LookComposerHost(
                client: client,
                // A composer that dismisses itself on success answers "did it
                // work?" with silence, and there is no looks surface to land
                // on yet. So the shell says it, in the composer's own words —
                // which are the honest ones: GLO-189 forbids implying a review,
                // and there is no audience to imply either.
                onSaved: {
                    lookOpen = false
                    notice = "saved to your account. nothing shows it to anyone yet."
                },
                onClose: { lookOpen = false }
            )
            .id(lookTrip)
        }
    }
}

extension LookTagSearch {
    /// Sean's ruling, Aug 31 (GLO-266's one open question, now closed): the
    /// tag search is the SHELF — "opens up a search of our shelf and allows
    /// users to go through and add items based on category, name, type."
    ///
    /// One fetch, filtered in memory: a shelf is hundreds of rows at its
    /// wildest, and the match fields — brand, name, variant, category — are
    /// all on the row already. `scope: .shelf` is declared, not inferred, so
    /// the picker's copy tells the truth about what it covers.
    static func overShelf(_ shelf: ShelfRepository) -> LookTagSearch {
        LookTagSearch(scope: .shelf) { query in
            let rows = try await shelf.shelf()
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return rows
                .filter { row in
                    guard !needle.isEmpty else { return true }
                    return row.productName.lowercased().contains(needle)
                        || row.brandName.lowercased().contains(needle)
                        || row.categoryLabel.lowercased().contains(needle)
                        || (row.variantLabel?.lowercased().contains(needle) ?? false)
                }
                .map { row in
                    TagSearchResult(
                        variantID: row.variantID,
                        // The row's own rendering — brand, product, and the
                        // shade when there is one. Never reassembled by the
                        // picker (its rule: it must not invent a shade name).
                        label: [row.brandName, row.productName].joined(separator: " ")
                            + (row.variantLabel.map { " · \($0)" } ?? ""),
                        category: TagCategory(slug: row.categorySlug, label: row.categoryLabel),
                        isOnYourShelf: true
                    )
                }
        }
    }
}

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
        let media: [LookMedia]
        let board: LookTagBoard
        let linkedRoutines: [LinkablePick]
        let linkedCollections: [LinkablePick]
    }

    @State private var post: LoadedPost?
    @State private var failed = false

    var body: some View {
        Group {
            if let post {
                LookPostView(
                    caption: post.caption, media: post.media, board: post.board,
                    linkedRoutines: post.linkedRoutines,
                    linkedCollections: post.linkedCollections,
                    // `mine()` is what loaded this post, so the viewer IS the
                    // owner — the editor is unconditional here, and becomes
                    // conditional the day a stranger's look renders.
                    linkEditor: linkEditor,
                    onClose: onClose
                )
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

    private var linkEditor: LookLinkEditor {
        let links = LinksRepository(client: client)
        let routines = RoutinesRepository(client: client)
        let collections = CollectionsRepository(client: client)
        let lookID = lookID
        return LookLinkEditor(
            linkables: {
                async let mine = routines.mine()
                async let theirs = collections.mine()
                return try await LookLinkables(
                    routines: mine.map { LinkablePick(id: $0.routineID, title: $0.title) },
                    collections: theirs.map { LinkablePick(id: $0.collectionID, title: $0.title) }
                )
            },
            link: { routineIDs, collectionIDs in
                try await links.link(lookID: lookID, routineIDs: routineIDs, collectionIDs: collectionIDs)
            },
            unlinkRoutine: { try await links.unlink(lookID: lookID, routineID: $0) },
            unlinkCollection: { try await links.unlink(lookID: lookID, collectionID: $0) }
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
            let media = look.photos.map { photo in
                // No read path exists for look photos yet — storage_presign
                // signs PUTs only. `.unavailable` says so on the page instead
                // of spinning at a URL that cannot be built.
                LookMedia(id: photo.photoID, position: photo.position, kind: .photo(.unavailable))
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
                caption: look.caption, media: media, board: LookTagBoard(spots),
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
