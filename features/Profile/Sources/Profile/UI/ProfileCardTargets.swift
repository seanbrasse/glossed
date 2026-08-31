import DesignSystem
import SwiftUI

// The cards' tap-target modifiers, split from `ProfileCards.swift` when the
// open door (GLO-272) pushed it past the 300-line ceiling.

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

    /// The click-in (GLO-272): outside edit mode the whole card opens its
    /// detail. Nil `open` renders the card untappable — no dead doors.
    @ViewBuilder
    func openTarget(
        enabled: Bool, label: String, open: (() -> Void)?
    ) -> some View {
        if enabled, let open {
            Button(action: open) { self }
                .buttonStyle(.plain)
                .accessibilityLabel("open \(label)")
        } else {
            self
        }
    }
}
