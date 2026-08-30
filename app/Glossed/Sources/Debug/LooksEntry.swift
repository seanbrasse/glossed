#if DEBUG

    import DataKit
    import DesignSystem
    import Looks
    import SwiftUI
    import UIKit

    /// The composer's states, in the catalog from birth — the sweep's first
    /// lesson was that states nobody can reach are states nobody drives.
    ///
    /// The minor state is deliberately NOT here: a minor is never offered the
    /// composer at all (the door is absent, the DB is the gate — 0043), so
    /// there is no composer state to show. Asserting the door's absence is an
    /// AppShell drive, not a fixture.
    @MainActor
    enum LooksEntry {
        static let empty = ScreenEntry(
            id: "looks-composer",
            title: "composer · empty",
            note: "no photo, no post — the button stays down until a photo exists, "
                + "and the add tile is the only affordance offered"
        ) {
            ComposerView(model: ComposerModel(store: savingStore), onPickPhoto: {})
        }

        static let composed = ScreenEntry(
            id: "looks-composer-full",
            title: "composer · one photo, two tags",
            note: "tags list from YOUR shelf (shade named), untag inline, "
                + "and the honesty line: nothing shows anyone this yet"
        ) {
            composerOnLaunch(photos: 1, failing: false)
        }

        static let extreme = ScreenEntry(
            id: "looks-composer-six",
            title: "composer · six photos",
            note: "the cap at the door: the add tile is ABSENT at six, never disabled — "
                + "GLO-88's family, designed out rather than discovered"
        ) {
            composerOnLaunch(photos: 6, failing: false)
        }

        static let saveFailed = ScreenEntry(
            id: "looks-composer-failed",
            title: "composer · the save failed",
            note: "loses NOTHING: caption, photos and tags all survive, the failure "
                + "names itself, and the retry is live"
        ) {
            composerOnLaunch(photos: 1, failing: true, thenPost: true)
        }

        /// The look card's media carousel (GLO-235), at the frame's own
        /// drawn default: `G.Feed` hardcodes `post.shots` as an array of
        /// three, so three is the case the design actually decided.
        static let mediaDeck = ScreenEntry(
            id: "looks-media-deck",
            title: "look media · three photos",
            note: "the kit's stacked deck, not a filmstrip: fanned right, the top card tilts "
                + "under your thumb, past 55pt it turns. 'added 3 photos' is the indicator — "
                + "a look post is attributed content, so there is no n on it anywhere"
        ) {
            deck(3)
        }

        static let mediaSingle = ScreenEntry(
            id: "looks-media-single",
            title: "look media · one photo",
            note: "one page shows NO pager chrome: no count line, no fan, nothing to swipe. "
                + "the frame hardcodes three shots and never met this case"
        ) {
            deck(1)
        }

        // MARK: - fixtures

        /// Drawn tiles as photo bytes, in `position` order — deliberately
        /// handed over shuffled so the fixture exercises the deck's sort
        /// rather than agreeing with it by accident.
        private static func deck(_ count: Int) -> some View {
            let tints: [UIColor] = [.systemPink, .systemTeal, .systemIndigo, .systemOrange]
            let media = (0 ..< count).map { index in
                LookMedia(position: index, kind: .photo(.data(tileData(tints[index % tints.count]))))
            }
            return VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text("LOOK MEDIA").eyebrow()
                LookMediaPager(media.reversed())
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Space.s5)
            .background(Tokens.Ground.milk)
        }

        private static let savingStore = LooksStore(
            save: { _, _, _ in UUID() },
            searchShelf: { _ in [] }
        )

        private static let failingStore = LooksStore(
            save: { _, _, _ in throw GlossedError.offline },
            searchShelf: { _ in [] }
        )

        /// A solid tile as photo bytes — the composer renders whatever data it
        /// is handed, and a drawn swatch keeps the fixture self-contained.
        private static func tileData(_ color: UIColor) -> Data {
            let renderer = UIGraphicsImageRenderer(size: .init(width: 300, height: 380))
            let image = renderer.image { context in
                color.setFill()
                context.fill(.init(x: 0, y: 0, width: 300, height: 380))
            }
            return image.jpegData(compressionQuality: 0.8) ?? Data()
        }

        private static func composerOnLaunch(photos: Int, failing: Bool, thenPost: Bool = false) -> some View {
            let model = ComposerModel(store: failing ? failingStore : savingStore)
            let tints: [UIColor] = [
                .systemPink, .systemTeal, .systemIndigo, .systemOrange, .systemBrown, .systemMint
            ]
            for index in 0 ..< photos {
                model.addPhoto(tileData(tints[index % tints.count]))
            }
            model.caption = "golden hour, favorites on"
            model.tag(
                ShelfTagCandidate(variantID: UUID(), label: "fenty pro filt'r · 330"),
                x: 0.3, y: 0.4
            )
            model.tag(
                ShelfTagCandidate(variantID: UUID(), label: "rare beauty soft pinch · joy"),
                x: 0.7, y: 0.6
            )
            return ComposerView(model: model, onPickPhoto: {})
                .task {
                    if thenPost {
                        model.post()
                        await model.saveTask?.value
                    }
                }
        }
    }
#endif
