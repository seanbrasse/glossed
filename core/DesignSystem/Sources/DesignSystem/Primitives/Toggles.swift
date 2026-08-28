import SwiftUI

/// Sticker checkbox: ink square, cherry-soft fill and a check glyph when on.
public struct GlossedCheckbox: View {
    let label: String
    @Binding var isOn: Bool

    public init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: Tokens.Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? Tokens.Cherry.soft : Tokens.Ground.card)
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Tokens.Ink.primary)
                    }
                }
                .frame(width: 22, height: 22)
                Text(label)
                    .font(.system(size: Typography.Size.small, weight: .semibold))
                    .foregroundStyle(Tokens.Ink.primary)
            }
            .frame(minHeight: Tokens.hitTarget, alignment: .leading)
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.pop(), value: isOn)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Pill switch with a sticker knob — mint when on, per the semantic palette.
public struct GlossedSwitch: View {
    let label: String?
    @Binding var isOn: Bool

    public init(isOn: Binding<Bool>, label: String? = nil) {
        _isOn = isOn
        self.label = label
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: Tokens.Space.s3) {
                if let label {
                    Text(label)
                        .font(.system(size: Typography.Size.small, weight: .semibold))
                        .foregroundStyle(Tokens.Ink.primary)
                    Spacer(minLength: Tokens.Space.s2)
                }
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Tokens.Support.mintSoft : Tokens.Ground.milk)
                    Capsule()
                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin)
                    Circle()
                        .fill(isOn ? Tokens.Support.mint : Tokens.Ground.card)
                        .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: 1.5))
                        .padding(2.5)
                }
                .frame(width: 50, height: 29)
            }
            .frame(minHeight: Tokens.hitTarget)
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.pop(Tokens.Motion.med), value: isOn)
        .accessibilityLabel(label ?? "toggle")
        .accessibilityValue(isOn ? "on" : "off")
    }
}
