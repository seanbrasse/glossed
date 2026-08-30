import DesignSystem
import SwiftUI

/// `G.Profile`'s rename sheet: grab handle, an eyebrow naming what is being
/// renamed, a pill input, then `save` + `cancel`.
///
/// **A presented sheet, not an in-view overlay, and driving it settled that.**
/// The first version built scrim + panel in a `ZStack` the way
/// `AppShellDrawer` does, which is what the frame draws (`position:absolute;
/// inset:0` under a `zIndex:51` panel). On device the floating nav sat **on
/// top of it and covered `save`** — the drawer gets away with that shape only
/// because it lives in `AppShell`, above the nav, and a feature cannot reach
/// there. A presented sheet covers the window, which is the behaviour the
/// kit's `zIndex:51` is expressing.
///
/// The surface is the system's, styled to the frame's `22px 22px 0 0` and
/// `--card`. `GlossedSheet` was tried first and left a transparent band under
/// the buttons: a detent is a fixed height, its content is not, and the two
/// only agree by accident. Every other sheet this screen presents — settings,
/// the stranger preview, linked socials — is a plain system sheet, so this is
/// also the consistent choice rather than only the working one.
///
/// What it costs against the frame: the rise is the platform's rather than
/// `sheetUp 300ms cubic-bezier(.2,.9,.3,1.3)`, the dimming is the platform's
/// rather than `rgba(27,25,23,.45)`, and there is no 2px ink border. A
/// reachable `save` is not a trade.
extension View {
    func renameSheet(model: ProfileTabsModel) -> some View {
        sheet(item: Binding(get: { model.renaming }, set: { model.renaming = $0 })) { _ in
            RenameSheet(model: model)
                .presentationDetents([.height(230)])
                .presentationBackground(Tokens.Ground.card)
                .presentationCornerRadius(22)
                .presentationDragIndicator(.visible)
        }
    }
}

/// `G.Profile`'s rename sheet: an eyebrow naming what is being renamed, a pill
/// input, then `save` + `cancel`.
struct RenameSheet: View {
    @Bindable var model: ProfileTabsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text(model.renaming?.eyebrow ?? "").eyebrow()
            // `GlossedInput`, not a hand-styled field: features compose
            // primitives, and it already carries GLO-57's typing rules — a
            // routine called "laneige" must not autocorrect to "lineage". Its
            // capsule is card-filled where the frame's is milk; that is the
            // primitive's choice and applies app-wide.
            GlossedInput("name it", text: $model.renaming.value)
            buttons
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Space.s5)
        .padding(.top, Tokens.Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
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
