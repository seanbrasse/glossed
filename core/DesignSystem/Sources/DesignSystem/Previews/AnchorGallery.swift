import SwiftUI

#Preview("anchor + evidence") {
    AnchorPreview()
        .padding(Tokens.Space.s5)
        .background(Tokens.Ground.milk)
        .task { Typography.registerFonts() }
}

private struct AnchorPreview: View {
    @State private var fit: Set<FitAnswer> = [.justRight]
    @State private var hair: String? = "3b"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                FitControl(selection: $fit)
                ConfidenceMeter(have: 2, need: 5)

                GapCard(
                    title: "facial sunscreen",
                    subtitle: "you have none logged",
                    peopleCount: 14,
                    onAccept: {},
                    onDismiss: { _ in }
                )

                Text("HAIR TYPE · ASKED, NEVER INFERRED").eyebrow()
                HairTypePicker(selection: $hair)
            }
        }
    }
}
