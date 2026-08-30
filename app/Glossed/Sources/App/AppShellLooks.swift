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

    init(client: GlossedClient, onSaved: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onSaved = onSaved
        self.onClose = onClose
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
