import DesignSystem
import SwiftUI

/// `G.OnbBuild` — the shelf starter: four doors and a skip, with the
/// starter's progress worn as a badge.
///
/// Stated divergence from the frame: the frame draws an inline "found it —
/// did it fit?" state. Building that would be a SECOND logging path
/// parallel to the ladder (which already owns search, scan, the fit-at-log
/// prompt, and the idempotent write) — the two-doors-one-row doctrine says
/// hand off instead. Every door here routes into a real flow; the fit
/// question meets the user inside it, exactly where it meets them
/// everywhere else.
///
/// Doors render only when wired (the full-page rule): "snap a photo" has
/// no flow behind it anywhere yet, so the app leaves its closure nil and
/// the card does not exist rather than dead-ending.
public struct OnbBuildView: View {
    /// The starter's progress — how many the new shelf holds, of the
    /// starter's goal. The badge only renders once something is added.
    private let addedCount: Int
    private let onScan: (() -> Void)?
    private let onSnapPhoto: (() -> Void)?
    private let onImport: (() -> Void)?
    private let onSearch: (() -> Void)?
    private let onSkip: () -> Void

    public init(
        addedCount: Int = 0,
        onScan: (() -> Void)? = nil,
        onSnapPhoto: (() -> Void)? = nil,
        onImport: (() -> Void)? = nil,
        onSearch: (() -> Void)? = nil,
        onSkip: @escaping () -> Void
    ) {
        self.addedCount = addedCount
        self.onScan = onScan
        self.onSnapPhoto = onSnapPhoto
        self.onImport = onImport
        self.onSearch = onSearch
        self.onSkip = onSkip
    }

    /// "2 of 5 added" — the badge's words, one place.
    public nonisolated static func progressLine(added: Int, goal: Int = 5) -> String {
        "\(added) of \(goal) added"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    Text("YOU\u{2019}VE SEEN IT · NOW MAKE IT YOURS").eyebrow()
                    Text("build your\nshelf")
                        .font(Typography.display(32))
                        .tracking(-0.64)
                        .foregroundStyle(Tokens.Ink.primary)
                        .padding(.top, 12)
                    if addedCount > 0 {
                        Badge(Self.progressLine(added: addedCount), tone: .butter)
                    }
                    VStack(spacing: Tokens.Space.s2) {
                        if let onScan {
                            door(Door(
                                title: "scan a barcode", line: "point at the upc — instant match",
                                symbol: "barcode.viewfinder", tint: Tokens.Support.mintSoft
                            ), onScan)
                        }
                        if let onSnapPhoto {
                            door(Door(
                                title: "snap a photo", line: "we read the label, you confirm",
                                symbol: "camera", tint: Tokens.Cherry.soft
                            ), onSnapPhoto)
                        }
                        if let onImport {
                            door(Door(
                                title: "import a list", line: "notes · csv · a screenshot",
                                symbol: "doc.text", tint: Tokens.Support.butterSoft
                            ), onImport)
                        }
                        if let onSearch {
                            door(Door(
                                title: "search the catalog", line: "type-ahead, then the ladder",
                                symbol: "magnifyingglass", tint: Tokens.Support.lilacSoft
                            ), onSearch)
                        }
                    }
                    .padding(.top, Tokens.Space.s4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("skip for now — I\u{2019}ll add later →", action: onSkip)
                .buttonStyle(.plain)
                .font(Typography.mono())
                .foregroundStyle(Tokens.Semantic.accentText)
                .underline()
                .frame(maxWidth: .infinity)
                .padding(.top, Tokens.Space.s3)
        }
        .padding(.init(top: 18, leading: 22, bottom: 22, trailing: 22))
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
            HStack(spacing: Tokens.Space.s3) {
                Image(systemName: door.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Tokens.Ink.primary)
                    .frame(width: 42, height: 42)
                    .background(door.tint)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.md)
                            .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(door.title)
                        .font(Typography.display(15.5, weight: 700))
                        .foregroundStyle(Tokens.Ink.primary)
                    Text(door.line).meta()
                }
                Spacer(minLength: 0)
            }
            .padding(.init(top: 12, leading: 14, bottom: 12, trailing: 14))
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
                .offset(x: Tokens.Shadow.md, y: Tokens.Shadow.md)
        )
    }
}
