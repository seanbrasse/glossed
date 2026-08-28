import SwiftUI

#Preview("controls — segmented, checkbox, switch") {
    ControlsPreview()
        .padding(Tokens.Space.s5)
        .background(Tokens.Ground.milk)
        .task { Typography.registerFonts() }
}

private struct ControlsPreview: View {
    @State private var domains: Set<String> = ["makeup", "skincare"]
    @State private var scope = "your shade"
    @State private var fragranceFree = true
    @State private var rankNudges = true

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Text("SHELF FILTER · MULTI + ALL").eyebrow()
            Segmented(
                options: ["makeup", "skincare", "haircare", "fragrance"],
                selection: $domains,
                allowsAll: true
            )
            Text("\(domains.count) of 4").meta()

            Text("LEADERBOARD SCOPE · SINGLE").eyebrow()
            Segmented(options: ["your shade", "everyone"], selection: $scope)

            Text("TOGGLES").eyebrow()
            GlossedCheckbox("fragrance-free only", isOn: $fragranceFree)
            GlossedSwitch(isOn: $rankNudges, label: "rank nudges")
        }
    }
}
