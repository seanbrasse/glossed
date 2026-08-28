import SwiftUI

/// Ink-bordered segmented control. Single-select by default; `multi` turns it
/// into the four-domain shelf filter, where `allowsAll` adds the "all" shortcut
/// that selects every option in one tap (kit: `Segmented multi all`).
public struct Segmented: View {
    let options: [String]
    let multi: Bool
    let allowsAll: Bool
    @Binding var selection: Set<String>

    /// Single-select convenience: binds one value instead of a set.
    public init(options: [String], selection: Binding<String>) {
        self.options = options
        multi = false
        allowsAll = false
        _selection = Binding(
            get: { [selection.wrappedValue] },
            set: {
                if let first = $0.first {
                    selection.wrappedValue = first
                }
            }
        )
    }

    /// Multi-select: `allowsAll` prepends the "all" shortcut.
    public init(options: [String], selection: Binding<Set<String>>, allowsAll: Bool = false) {
        self.options = options
        multi = true
        self.allowsAll = allowsAll
        _selection = selection
    }

    private var allSelected: Bool {
        selection.count == options.count
    }

    public var body: some View {
        HStack(spacing: 3) {
            if multi, allowsAll {
                segment(label: "all", on: allSelected) {
                    selection = allSelected ? [] : Set(options)
                }
            }
            ForEach(options, id: \.self) { option in
                segment(label: option, on: selection.contains(option)) { toggle(option) }
            }
        }
        .padding(3)
        .background(Tokens.Ground.card)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
        .background(
            Capsule().fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
        )
    }

    private func toggle(_ option: String) {
        selection = Segmented.next(from: selection, toggling: option, multi: multi)
    }

    /// Pure selection rule, extracted so the invariant is testable:
    /// multi-select never empties (an empty domain filter would show nothing).
    static func next(from current: Set<String>, toggling option: String, multi: Bool) -> Set<String> {
        guard multi else { return [option] }
        var next = current
        if next.contains(option) {
            next.remove(option)
        } else {
            next.insert(option)
        }
        return next.isEmpty ? current : next
    }

    private func segment(label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(on ? Color.white : Tokens.Ink.primary)
                .padding(.horizontal, Tokens.Space.s3)
                .frame(minHeight: 34)
                .frame(maxWidth: .infinity)
                .background(on ? Tokens.Ink.primary : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.pop(), value: on)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
