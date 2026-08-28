import SwiftUI

/// The n, everywhere a claim appears. Counts go through this view, never
/// ad-hoc mono text — no claim without its n (design sheet §08).
public struct EvidenceLine: View {
    public enum Tone {
        case soft, ink
        var color: Color {
            self == .soft ? Tokens.Ink.soft : Tokens.Ink.primary
        }
    }

    let n: Int
    let of: Int?
    let label: String
    let empty: String?
    let tone: Tone

    public init(n: Int, of: Int? = nil, label: String, empty: String? = nil, tone: Tone = .soft) {
        self.n = n
        self.of = of
        self.label = label
        self.empty = empty
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 5) {
            if isEmpty {
                Text(empty ?? "not enough data yet").meta()
            } else {
                Circle().fill(Tokens.Cherry.base).frame(width: 5, height: 5)
                Text(countText).meta(color: tone.color)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var isEmpty: Bool {
        n == 0 || (empty != nil && n < 5)
    }

    private var countText: String {
        if let of {
            "\(n) of \(of) \(label)"
        } else {
            "\(n) \(label)"
        }
    }
}
