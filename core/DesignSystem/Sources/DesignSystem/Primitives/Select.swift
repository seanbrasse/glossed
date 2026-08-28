import SwiftUI

/// Pill select backed by the native menu — one decision, no custom wheel.
/// Options are lowercase strings; the caller maps them to domain values.
public struct GlossedSelect: View {
    let label: String?
    let options: [String]
    @Binding var selection: String

    public init(options: [String], selection: Binding<String>, label: String? = nil) {
        self.options = options
        _selection = selection
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            if let label {
                Text(label).meta()
            }
            Menu {
                Picker("", selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
            } label: {
                HStack(spacing: Tokens.Space.s2) {
                    Text(selection)
                        .font(.system(size: Typography.Size.body, weight: .semibold))
                        .foregroundStyle(Tokens.Ink.primary)
                    Spacer(minLength: Tokens.Space.s2)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Tokens.Ink.soft)
                }
                .padding(.horizontal, Tokens.Space.s4)
                .frame(minHeight: Tokens.hitTarget)
                .background(Tokens.Ground.card)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair))
            }
            .accessibilityLabel(label ?? "select")
            .accessibilityValue(selection)
        }
    }
}
