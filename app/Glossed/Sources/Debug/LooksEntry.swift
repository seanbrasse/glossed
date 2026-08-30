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

        // MARK: - fixtures

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
