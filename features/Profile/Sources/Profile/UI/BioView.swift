import DataKit
import DesignSystem
import SwiftUI

/// The bio a stranger reads. GLO-204.
///
/// No kit frame — `G.Profile` renders a bio and never offers to write one — so
/// this is built from the design system.
///
/// Prose, and the primitive already ruled on that: `GlossedTextArea`
/// "deliberately has no `typing` option … everything that has ever gone in one
/// is prose a person wrote to be read", so it keeps the system default while
/// `GlossedInput` defaults to `.plain` (GLO-57). Driving this confirmed the
/// consequence — a typed "soft glam" stores as "Soft glam". That is the
/// design system's decision, not this screen's to reverse: the name field
/// gets `.never` because a name is an identifier, and a bio is sentences.
struct BioView: View {
    @State private var model: BioModel
    private let onBack: () -> Void

    init(store: BioStore, onBack: @escaping () -> Void) {
        _model = State(wrappedValue: BioModel(store: store))
        self.onBack = onBack
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Button("← back", action: onBack)
                    .buttonStyle(.plain)
                    .font(Typography.mono(Typography.Size.meta))
                    .foregroundStyle(Tokens.Cherry.deep)

                Text("your bio")
                    .font(Typography.display(Typography.Size.h2))
                    .foregroundStyle(Tokens.Ink.primary)

                Text("a line or two on your profile, under your name.")
                    .font(.system(size: Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.soft)
                    .fixedSize(horizontal: false, vertical: true)

                GlossedTextArea(text: $model.typed)

                Button("save") {
                    Task { await model.save() }
                }
                .buttonStyle(.glossed(.primary, block: true))
                .disabled(!model.canSave)

                // Read back from the row, never assumed. See BioModel.
                Text(model.statusLine)
                    .font(.system(size: Typography.Size.meta))
                    .foregroundStyle(Tokens.Ink.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await model.load() }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Toast(message).padding(.bottom, Tokens.Space.s8)
            }
        }
    }
}
