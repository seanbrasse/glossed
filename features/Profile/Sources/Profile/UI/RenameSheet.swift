import DesignSystem
import SwiftUI

/// `G.Profile`'s rename sheet: grab handle, an eyebrow naming what is being
/// renamed, a pill input, then `save` + `cancel`.
///
/// `GlossedSheet` already carries the frame's geometry — the 44×4 handle and
/// the `22 22 0 0` radius are its own — so this is the sheet's contents and
/// nothing else. The scrim and the rise are the platform's: the frame animates
/// `sheetUp 300ms cubic-bezier(.2,.9,.3,1.3)` because a web page has to, and
/// `Tokens.Motion.pop` is that same curve. A presented sheet already does it.
/// Scrim + sheet, as `AppShellDrawer` builds the `+` drawer and as the frame
/// draws this one — an `inset:0` scrim under an absolutely-positioned panel.
///
/// **The `if` is inside the `ZStack` on purpose**, and that is inherited
/// knowledge rather than taste: wrapping both in one container and moving the
/// container makes the scrim travel with the sheet, a hard-edged rectangle
/// wiping up the screen. `AppShellDrawer` has the measurement written down.
/// So the scrim **fades** on a curve that does not overshoot, and the sheet
/// **moves** and keeps `pop` — whose 1.3 control point is the kit's own
/// `sheetUp 300ms cubic-bezier(.2,.9,.3,1.3)`.
struct RenameOverlay: View {
    @Bindable var model: ProfileTabsModel

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.renaming != nil {
                scrim
                RenameSheet(model: model)
                    .transition(.move(edge: .bottom).animation(Tokens.Motion.pop(Tokens.Motion.med)))
            }
        }
        .ignoresSafeArea()
    }

    /// The frame's `rgba(27,25,23,.45)` — `--ink` at 45%.
    private var scrim: some View {
        Button { model.renaming = nil } label: {
            Rectangle().fill(Tokens.Ink.primary.opacity(0.45))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("close")
        .transition(.opacity.animation(.easeOut(duration: Tokens.Motion.med)))
    }
}

struct RenameSheet: View {
    @Bindable var model: ProfileTabsModel

    var body: some View {
        GlossedSheet {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text(model.renaming?.eyebrow ?? "").eyebrow()
                // `GlossedInput`, not a hand-styled field: features compose
                // primitives, and it already carries GLO-57's typing rules —
                // a routine called "laneige" must not autocorrect to "lineage".
                // Its capsule is card-filled where the frame's is milk; that is
                // the primitive's choice and applies app-wide.
                GlossedInput("name it", text: $model.renaming.value)
                buttons
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: Tokens.Space.s3) {
            Button("save") { Task { await model.saveRename() } }
                .buttonStyle(.glossed(.primary, block: true))
                .disabled(model.isSavingRename)
            Button("cancel") { model.renaming = nil }
                .buttonStyle(.glossed(.secondary))
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// The frame's edit affordance on a card: a pencil badge top-right, and the
/// whole card as the tap target.
///
/// A `Button` wrapping the card rather than an overlay button on it, because
/// the frame's own element is `<button onClick={()=> editing && setRename(…)}>`
/// — the card IS the control while editing, and a second tap target inside it
/// would be two ways to do one thing.
///
/// **There is no button at all when not editing**, and that is a fix rather
/// than a shortcut. The first version wrapped the card unconditionally and
/// used `.disabled(!editing)`; driving it showed every routine and collection
/// title rendering grey, because a disabled button greys its whole label
/// subtree and a card is a label. `GlossedButtonStyle` fades deliberately at
/// 45% for exactly this reason (GLO-76) — `.plain` does it invisibly.
extension View {
    @ViewBuilder
    func renameTarget(
        editing: Bool, label: String, action: @escaping () -> Void
    ) -> some View {
        if editing {
            Button(action: action) {
                self.overlay(alignment: .topTrailing) {
                    EditBadge().padding(Tokens.Space.s2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("rename \(label)")
        } else {
            self
        }
    }
}

/// `TextField` needs a non-optional binding; the sheet is only ever presented
/// with a target. Writing through to `.value` keeps the typed text on the model
/// so a failed save can leave the sheet open with the words still in it.
private extension Binding where Value == RenameTarget? {
    var value: Binding<String> {
        Binding<String>(
            get: { wrappedValue?.value ?? "" },
            set: { typed in
                guard var target = wrappedValue else { return }
                target.value = typed
                wrappedValue = target
            }
        )
    }
}
