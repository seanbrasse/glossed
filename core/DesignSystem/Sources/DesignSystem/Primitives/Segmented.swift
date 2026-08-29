import SwiftUI

/// Ink-bordered segmented control. Single-select by default; `multi` turns it
/// into the four-domain shelf filter, where `allowsAll` adds the "all" shortcut
/// that selects every option in one tap (kit: `Segmented multi all`).
public struct Segmented: View {
    /// What frames the row. `.capsule` is the kit's original — card fill, ink
    /// border, hard shadow. `.bare` drops the outer container and lets the
    /// segments float (Sean's Aug 29 direction for the shelf's domain filter:
    /// the row already sits in its own band, and a container inside a band
    /// reads as a box in a box).
    public enum Chrome {
        case capsule, bare
    }

    let options: [String]
    let multi: Bool
    let allowsAll: Bool
    let chrome: Chrome
    @Binding var selection: Set<String>

    /// Single-select convenience: binds one value instead of a set.
    public init(options: [String], selection: Binding<String>, chrome: Chrome = .capsule) {
        self.options = options
        multi = false
        allowsAll = false
        self.chrome = chrome
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
    public init(
        options: [String],
        selection: Binding<Set<String>>,
        allowsAll: Bool = false,
        chrome: Chrome = .capsule
    ) {
        self.options = options
        multi = true
        self.allowsAll = allowsAll
        self.chrome = chrome
        _selection = selection
    }

    private var allSelected: Bool {
        selection.count == options.count
    }

    public var body: some View {
        switch chrome {
        case .capsule:
            row
                .padding(3)
                .background(Tokens.Ground.card)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
                .background(
                    Capsule().fill(Tokens.Ink.primary)
                        .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
                )
        case .bare:
            row
        }
    }

    private var row: some View {
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
