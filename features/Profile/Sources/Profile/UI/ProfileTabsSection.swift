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

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if model.canEdit {
                editRow
            }
            if model.tabs.count > 1 {
                ProfileTabBar(
                    tabs: model.tabs, mark: model.mark(for:), selection: $model.tab
                )
            }
            content
        }
    }

    /// The frame's `edit profile` / `done editing`, its variant flipping
    /// secondary → mint, with the mono hint beside it while editing.
    private var editRow: some View {
        HStack(spacing: Tokens.Space.s2) {
            Button(model.editButtonLabel) { model.toggleEditing() }
                .buttonStyle(.glossed(model.isEditing ? .mint : .secondary, size: .sm))
            if let hint = model.editHint {
                Text(hint).meta()
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            ProgressView().frame(maxWidth: .infinity)
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
        grid(model.looks, empty: "no looks yet", says: emptyLine(.look)) { LookTile(look: $0) }
    }

    private var collections: some View {
        grid(model.collections, empty: "no collections yet", says: emptyLine(.collection)) { collection in
            CollectionCard(collection: collection)
                .renameTarget(editing: model.isEditing, label: collection.title) {
                    model.beginRename(
                        RenameTarget(kind: .collection, id: collection.id, value: collection.title)
                    )
                }
        }
    }

    private var shelf: some View {
        grid(model.shelf, empty: "nothing on your shelf yet", says: "log something you own and it lands here.") {
            ShelfTile(entry: $0)
        }
    }

    /// Routines stay a single column: a routine card carries its numbered
    /// steps, and two of those side by side wrap every step line.
    @ViewBuilder private var routines: some View {
        if model.routines.isEmpty {
            emptyPane("no routines yet", emptyLine(.routine))
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                ForEach(model.routines) { routine in
                    RoutineCard(routine: routine)
                        .renameTarget(editing: model.isEditing, label: routine.title) {
                            model.beginRename(
                                RenameTarget(kind: .routine, id: routine.routineID, value: routine.title)
                            )
                        }
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
