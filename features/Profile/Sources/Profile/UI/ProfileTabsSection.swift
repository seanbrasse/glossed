import DataKit
import DesignSystem
import SwiftUI

/// The profile's body of work: the scoped tab strip and the grid it selects
/// (GLO-261).
///
/// Sean, after driving the merged screen: *"otherwise, users will see their
/// bio, pfp, name, and then looks as default, or collections, or routines,
/// etc."* Everything below the identity block is content; the only control is
/// the strip that chooses which content.
struct ProfileTabsSection: View {
    @Bindable var model: ProfileTabsModel
    /// Nil for a build whose app layer has wired no composer. The empty state
    /// then says what the profile holds and stops, rather than offering a `+`
    /// that opens nothing.
    let onCompose: ((ProfileComposable) -> Void)?
    /// Opens the editor for one identity field. Nil for a build whose app
    /// layer has wired no settings store — the rows then do not render, on
    /// the same rule as `onCompose`: no door onto a room with no floor.
    let onEditIdentity: ((ProfileIdentityField) -> Void)?
    /// Opens one look as a post (GLO-266). Nil until the app wires it — the
    /// tile then renders untappable, per the no-dead-doors rule.
    let onOpenLook: ((UUID) -> Void)?
    /// Opens one collection / routine as a detail screen (GLO-272 — "edited
    /// by clicking into them"). Same nil rule. Outside edit mode only: in
    /// edit mode the card is the rename target, one gesture per mode.
    let onOpenCollection: ((UUID) -> Void)?
    let onOpenRoutine: ((UUID) -> Void)?
    /// Opens the default want-to-try collection (batch 2). Same nil rule.
    let onOpenWantToTry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if model.tabs.count > 1 {
                ProfileTabBar(
                    tabs: model.tabs, mark: model.mark(for:), selection: $model.tab
                )
            }
            content
        }
    }

    /// The frame's `edit profile` / `done editing`, its variant flipping
    /// secondary → mint, with the mono hint beside it while editing — and,
    /// underneath while editing, the identity fields.
    ///
    /// **Sean's ruling, Aug 31:** *"Edit profile should allow users to update
    /// their bio, pfp, and maybe lock specific looks and routines and
    /// collections as private."* Name and bio land here. Both editors already
    /// existed and were reachable only through settings → your profile, so
    /// this opens a second door onto built screens rather than building any.
    ///
    /// The photo is not here: there is no photo column in the schema —
    /// `profiles` carries `avatar_seed` and nothing else — so it waits on a
    /// migration (GLO-275). Per-item locks are GLO-276.
    private var editRow: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            HStack(spacing: Tokens.Space.s2) {
                Button(model.editButtonLabel) { model.toggleEditing() }
                    .buttonStyle(.glossed(model.isEditing ? .mint : .secondary, size: .sm))
                if let hint = model.editHint {
                    Text(hint).meta()
                }
                Spacer(minLength: 0)
            }
            if model.isEditing, let onEditIdentity {
                HStack(spacing: Tokens.Space.s2) {
                    ForEach(ProfileIdentityField.allCases) { field in
                        Button(field.label) { onEditIdentity(field) }
                            .buttonStyle(.glossed(.secondary, size: .sm))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            // Rarely seen: the identity load usually finishes first and the
            // profile's own skeleton covers this. When it does show, it is
            // the grid's silhouette, not a spinner — same reason as there.
            HStack(spacing: Tokens.Space.s3) {
                ForEach(0 ..< 2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                        .fill(Tokens.Ground.line)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        } else if model.isEmpty {
            // Sean's `+`: one empty state for the whole profile, not one per
            // tab. See `ProfileTabsModel.isEmpty`.
            ProfileEmptyState(onCompose: onCompose)
        } else {
            switch model.tab {
            case .looks: looks
            case .collections: collections
            case .routines: routines
            case .shelf: shelf
            }
        }
    }

    // MARK: - The grids

    private var looks: some View {
        // Two columns rather than Instagram's three: with no photograph to
        // draw, a third column leaves a caption about eleven characters wide.
        grid(model.looks, empty: "no looks yet", says: emptyLine(.look)) { look in
            if let onOpenLook {
                Button {
                    onOpenLook(look.id)
                } label: {
                    LookTile(look: look)
                }
                .buttonStyle(.plain)
            } else {
                LookTile(look: look)
            }
        }
    }

    @ViewBuilder private var collections: some View {
        // The DEFAULT collection leads (batch 2) — always there when the
        // seam is wired: a default exists even empty, and the empty card
        // says what lands in it.
        if model.hasWantToTry {
            wantToTryLead
        }
        grid(model.collections, empty: "no collections yet", says: emptyLine(.collection)) { collection in
            CollectionCard(collection: collection)
                .renameTarget(editing: model.isEditing, label: collection.title) {
                    model.beginRename(
                        RenameTarget(kind: .collection, id: collection.id, value: collection.title)
                    )
                }
                .openTarget(
                    enabled: !model.isEditing, label: collection.title,
                    open: onOpenCollection.map { open in { open(collection.id) } }
                )
        }
    }

    /// Sized like a grid tile, not a banner: the frame's own two columns,
    /// with an empty second cell — the card leads, it does not shout.
    private var wantToTryLead: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Tokens.Space.s3),
                GridItem(.flexible())
            ],
            spacing: Tokens.Space.s3
        ) {
            WantToTryCard(entries: model.wantToTry)
                .openTarget(
                    enabled: !model.isEditing, label: "want to try",
                    open: onOpenWantToTry
                )
            Color.clear
        }
        .padding(.bottom, Tokens.Space.s3)
    }

    private var shelf: some View {
        grid(
            model.shelf, empty: "nothing on your shelf yet",
            says: "log something you own and it lands here."
        ) { ShelfTile(entry: $0) }
    }

    /// Routines stay a single column: a routine card carries its numbered
    /// steps, and two of those side by side wrap every step line.
    @ViewBuilder private var routines: some View {
        if model.routines.isEmpty {
            emptyPane("no routines yet", emptyLine(.routine))
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                ForEach(model.routines) { routine in
                    RoutineCard(
                        routine: routine,
                        links: model.routineLinks[routine.routineID] ?? [],
                        // The × rides EDIT MODE, the same gesture that renames
                        // — one mode, every mutation. Inner buttons hit-test
                        // first, so a chip tap unlinks and the card's body
                        // still opens the rename.
                        onUnlink: model.isEditing && model.canUnlinkCollections
                            ? { collectionID in
                                Task { await model.unlinkCollection(collectionID, from: routine.routineID) }
                            }
                            : nil
                    )
                    .renameTarget(editing: model.isEditing, label: routine.title) {
                        model.beginRename(
                            RenameTarget(kind: .routine, id: routine.routineID, value: routine.title)
                        )
                    }
                    .openTarget(
                        enabled: !model.isEditing, label: routine.title,
                        open: onOpenRoutine.map { open in { open(routine.routineID) } }
                    )
                }
            }
        }
    }

    /// The frame's `gridTemplateColumns:'1fr 1fr'` at `gap:12`.
    @ViewBuilder
    private func grid<T: Identifiable>(
        _ items: [T], empty: String, says: String, @ViewBuilder card: @escaping (T) -> some View
    ) -> some View {
        if items.isEmpty {
            emptyPane(empty, says)
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Tokens.Space.s3),
                    GridItem(.flexible(), spacing: Tokens.Space.s3)
                ],
                spacing: Tokens.Space.s3
            ) {
                ForEach(items) { card($0) }
            }
        }
    }

    /// One tab empty on a profile that is not. Never blank — it says what the
    /// thing is and where it is made. It does not offer to make one: the
    /// profile-wide `+` is the empty state's, and the shell's own `+` is
    /// everywhere else's. Two create affordances on one screen is one too many.
    private func emptyPane(_ title: String, _ line: String) -> some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text(title)
                    .font(Typography.display(Typography.Size.h3))
                    .foregroundStyle(Tokens.Ink.primary)
                Text(line).meta()
            }
        }
    }

    /// What each thing IS, in the app's own voice.
    ///
    /// None of it says who will see the thing. A look's audience depends on
    /// the looks scope and on GLO-26, which has not decided; a collection is
    /// created `only_you` and no surface in V1 widens it. Copy about a scope
    /// no screen controls is the GLO-208 shape (GLO-189).
    private func emptyLine(_ what: ProfileComposable) -> String {
        switch what {
        case .look: "a look is a photo of a face you made. start one from the + button."
        case .collection: "a collection is a group of things you own. make one from the + button."
        case .routine: "a routine is the order you use things in. build one from the + button."
        }
    }
}
