import DesignSystem
import SwiftUI

/// `G.OnbWelcome` — where to first? Three doors, each a real destination,
/// and the honest footer about why finding friends is not one of them.
public struct OnbWelcomeView: View {
    /// The first card's mono line carries the shelf starter's progress
    /// ("pick up where you left off — 2 of 5") — supplied by whoever knows
    /// it; the default is the no-progress phrasing.
    private let buildLine: String
    private let onBuild: () -> Void
    private let onImport: () -> Void
    private let onBrowse: () -> Void

    public init(
        buildLine: String = "search, scan, or create — your call",
        onBuild: @escaping () -> Void,
        onImport: @escaping () -> Void,
        onBrowse: @escaping () -> Void
    ) {
        self.buildLine = buildLine
        self.onBuild = onBuild
        self.onImport = onImport
        self.onBrowse = onBrowse
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("welcome in \u{273F}")
                .handAside()
                .rotationEffect(.degrees(-1.5))
            Text("where to\nfirst?")
                .font(Typography.display(38))
                .tracking(-1.14)
                .foregroundStyle(Tokens.Ink.primary)
                .padding(.top, 10)
            ScrollView {
                VStack(spacing: Tokens.Space.s3) {
                    door(Door(
                        title: "build your shelf", line: buildLine,
                        symbol: "square.split.1x2", tint: Tokens.Cherry.soft
                    ), onBuild)
                    door(Door(
                        title: "import a list", line: "notes, csv, a screenshot of a haul",
                        symbol: "doc.text", tint: Tokens.Support.butterSoft
                    ), onImport)
                    door(Door(
                        title: "just browse", line: "see what people in your shade love",
                        symbol: "sparkles", tint: Tokens.Support.mintSoft
                    ), onBrowse)
                }
                .padding(.vertical, Tokens.Space.s5)
            }
            Text("finding friends moved to phase 1.5 — V1 has nothing to show another person")
                .meta()
        }
        .padding(.init(top: 20, leading: 22, bottom: 22, trailing: 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.Ground.milk)
    }

    private struct Door {
        let title: String
        let line: String
        let symbol: String
        let tint: Color
    }

    private func door(_ door: Door, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: door.symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Tokens.Ink.primary)
                    .frame(width: 46, height: 46)
                    .background(door.tint)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.md)
                            .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(door.title)
                        .font(Typography.display(17))
                        .foregroundStyle(Tokens.Ink.primary)
                    Text(door.line).meta()
                }
                Spacer(minLength: 0)
            }
            .padding(.init(top: 16, leading: 14, bottom: 16, trailing: 14))
        }
        .buttonStyle(.plain)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        )
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.lg, y: Tokens.Shadow.lg)
        )
    }
}
