import DataKit
import Foundation

// The looks tab's row and its seam, lifted out of `ProfileTabsStores.swift`
// when GLO-274 gave `ProfileLook` a `visibility` — the field the tab's scope
// mark is a ceiling of — and took that file past SwiftLint's 300-line ceiling.
// Extract rather than trim the explanation, the same move `AccountStore` and
// `ShelfModels` made.

/// One tile of the looks grid.
///
/// **It carries no `r2_key` and no photograph, and that is the honest state of
/// the build rather than a simplification.** `LookPhoto.r2Key` is
/// storage-relative and the app composes URLs from its own config — but the
/// only base the app has is `storage/v1/object/public/catalog`, the catalog
/// bucket. Look photos are uploaded to R2 by presigned PUT and **nothing
/// anywhere resolves one back to a readable URL** (probed across `core`,
/// `features` and `app`). A grid that pointed tiles at a guessed base would
/// draw a wall of broken images.
///
/// A look photo is also regulated data (`docs/domain.md` §5). Keeping the key
/// off this struct means it cannot reach a log, an analytics prop or a
/// breadcrumb by way of a view that renders it.
public struct ProfileLook: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let caption: String?
    /// `MyLook.photoN` — this post's own photos. Chrome, and it reads as
    /// chrome: a look is attributed content, never a claim (GLO-196).
    public let photoN: Int
    /// `looks.state == 'public'`. `mine()` returns drafts too — that is the
    /// point of an owner-side read — so the tile has to say which is which.
    public let isPublished: Bool
    /// A signed URL for the FIRST photo (Sean, Aug 31: "a preview of the
    /// first image in the carousel or only image"). Nil renders the caption
    /// tile the grid always had — a preview is chrome, and a look whose
    /// photo did not sign is still a look.
    public let previewURL: URL?
    /// `looks.visibility` — this look's own scope since 0053 (GLO-272), which
    /// is what the tab's mark is a ceiling of. Carried for the same reason
    /// `ProfileCollection.visibility` is: the account holds no scope for looks
    /// any more, so the rows are the only place the answer lives.
    public let visibility: PrivacyScope

    public init(
        id: UUID,
        caption: String?,
        photoN: Int,
        isPublished: Bool,
        previewURL: URL? = nil,
        visibility: PrivacyScope = .onlyYou
    ) {
        self.id = id
        self.caption = caption
        self.photoN = photoN
        self.isPublished = isPublished
        self.previewURL = previewURL
        self.visibility = visibility
    }
}

/// The looks half of the seam.
public struct ProfileLooksStore: Sendable {
    public var mine: @Sendable () async throws -> [ProfileLook]

    public init(mine: @escaping @Sendable () async throws -> [ProfileLook]) {
        self.mine = mine
    }

    /// **Drafts are kept, not filtered.** `LooksRepository.mine()` returns
    /// every state, and this is your own profile — a draft you cannot see is a
    /// draft you cannot finish. The tile says `draft` on it, and the tab's
    /// scope mark says what happens to the published ones.
    /// `resolvePhotoURLs` is the app's seam onto the read path (GLO-272):
    /// this feature knows which photo comes first, the app knows how to sign
    /// it, and neither learns the other's half. One call for the whole grid.
    /// The default resolves nothing, so previews degrade to the caption tile
    /// rather than making the seam a requirement.
    public static func live(
        _ looks: LooksRepository,
        resolvePhotoURLs: @escaping @Sendable ([UUID]) async -> [UUID: URL] = { _ in [:] }
    ) -> ProfileLooksStore {
        ProfileLooksStore(mine: {
            let mine = try await looks.mine()
            let firstPhotos = Dictionary(
                uniqueKeysWithValues: mine.compactMap { look in
                    look.photos.first.map { (look.lookID, $0.photoID) }
                }
            )
            let urls = await resolvePhotoURLs(Array(firstPhotos.values))
            return mine.map {
                ProfileLook(
                    id: $0.lookID, caption: $0.caption,
                    photoN: $0.photoN, isPublished: $0.isPublished,
                    previewURL: firstPhotos[$0.lookID].flatMap { urls[$0] },
                    visibility: $0.visibility
                )
            }
        })
    }
}
