import SwiftUI

/// Mono count/label pill in a soft tone — `#2 of 5`, `fenty 240`, `26 items`.
public struct Badge: View {
    public enum Tone {
        case cherry, mint, lilac, butter

        var fill: Color {
            switch self {
            case .cherry: Tokens.Cherry.soft
            case .mint: Tokens.Support.mintSoft
            case .lilac: Tokens.Support.lilacSoft
            case .butter: Tokens.Support.butterSoft
            }
        }
    }

    let text: String
    let tone: Tone

    public init(_ text: String, tone: Tone = .cherry) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(Typography.mono(10.5, bold: true))
            .foregroundStyle(Tokens.Ink.primary)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(tone.fill)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Tokens.Ground.line, lineWidth: 1))
    }
}

/// Roadmap phase tag — spec surfaces only, never product UI.
public struct PhaseTag: View {
    public enum Phase: String {
        case v1 = "V1"
        case v15 = "V1.5"
        case v2 = "V2"

        var fill: Color {
            switch self {
            case .v1: Tokens.Cherry.base
            case .v15: Tokens.Support.butter
            case .v2: Tokens.Support.lilac
            }
        }

        var foreground: Color {
            self == .v15 ? Tokens.Ink.primary : .white
        }
    }

    let phase: Phase

    public init(_ phase: Phase) {
        self.phase = phase
    }

    public var body: some View {
        Text(phase.rawValue)
            .font(Typography.control(Typography.Size.tag, weight: .heavy))
            .kerning(Typography.Size.tag * 0.1)
            .foregroundStyle(phase.foreground)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(phase.fill)
            .clipShape(Capsule())
    }
}
