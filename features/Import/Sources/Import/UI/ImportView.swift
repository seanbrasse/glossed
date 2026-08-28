import DesignSystem
import SwiftUI

/// `G.Import` — the whole screen, in its two states: pick a source, then look
/// at what came back line by line.
///
/// The screen's argument is in its last line: *an import lands on your shelf
/// only — nothing is posted anywhere.* Everything above it is the machinery
/// that makes that safe to believe.
public struct ImportView: View {
    @State private var model: ImportModel
    private let onBack: () -> Void
    private let onLadder: (ImportLine) -> Void
    private let onAdd: () -> Void

    public init(
        model: ImportModel,
        onBack: @escaping () -> Void = {},
        onLadder: @escaping (ImportLine) -> Void = { _ in },
        onAdd: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.onBack = onBack
        self.onLadder = onLadder
        self.onAdd = onAdd
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button("← back", action: onBack)
                    .buttonStyle(.plain)
                    .font(Typography.mono(12))
                    .foregroundStyle(Tokens.Semantic.accentText)
                    .underline()
                Text("import your shelf")
                    .font(Typography.display(28))
                    .tracking(-0.56)
                    .foregroundStyle(Tokens.Ink.primary)
                // The one handwritten aside this screen is allowed. It is not
                // decoration: it is the whole pitch for the feature, which is
                // that nobody is being asked to start from nothing.
                // U+FE0E forces the text presentation of ✿. Without it iOS
                // renders it as a colour emoji, which puts a pink flower sticker
                // in the middle of a monochrome cherry-deep hand line. The kit
                // uses this character in several places, so the same fix is
                // owed anywhere else it appears.
                Text("you already have a list somewhere ✿\u{FE0E}")
                    .handAside()
                    .rotationEffect(Tokens.Rotate.r3)
                if model.source == nil {
                    sourcePicker
                } else {
                    parsePane
                }
            }
            // 110pt of bottom room: the floating nav sits over this screen.
            .padding(.init(top: 14, leading: 16, bottom: 110, trailing: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.Ground.milk)
    }

    // MARK: - Picking a source

    private var sourcePicker: some View {
        VStack(spacing: 10) {
            ForEach(ImportSource.allCases, id: \.self) { source in
                Button {
                    model.source = source
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: ImportView.glyph(for: source))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Tokens.Ink.primary)
                            .frame(width: 42, height: 42)
                            .background(ImportView.tint(for: source))
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin)
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(source.title)
                                .font(Typography.display(15.5, weight: 700))
                                .foregroundStyle(Tokens.Ink.primary)
                            Text(source.subtitle).meta()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tokens.Ground.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Tokens.Ink.primary)
                            .offset(x: Tokens.Shadow.md, y: Tokens.Shadow.md)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(source.title)
                .accessibilityHint(source.subtitle)
            }
        }
        .padding(.top, 2)
    }

    /// One tint per source, so three cards that are otherwise identical are
    /// still tellable apart at a glance.
    nonisolated static func tint(for source: ImportSource) -> Color {
        switch source {
        case .notes: Tokens.Support.butterSoft
        case .csv: Tokens.Support.mintSoft
        case .screenshot: Tokens.Cherry.soft
        }
    }

    /// SF Symbols where the kit draws its own `ICONS` — GLO-64.
    nonisolated static func glyph(for source: ImportSource) -> String {
        switch source {
        case .notes: "doc.text"
        case .csv: "list.bullet"
        case .screenshot: "camera"
        }
    }

    // MARK: - Looking at what came back

    @ViewBuilder
    private var parsePane: some View {
        if let source = model.source {
            Text(source.title).eyebrow()
        }
        editor
        counts
        lineList
        if model.addableCount > 0 {
            Button("add \(model.addableCount) to your shelf", action: onAdd)
                .buttonStyle(.glossed(block: true))
        }
        // The screen's whole argument, and the reason it is centred and last:
        // an import is the moment someone hands over a list they have kept
        // privately for years.
        Text("an import lands on your shelf only — nothing is posted anywhere")
            .meta()
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var editor: some View {
        TextEditor(text: $model.text)
            .font(Typography.mono(12))
            .lineSpacing(4)
            .foregroundStyle(Tokens.Ink.primary)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 110)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Tokens.Ground.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
            )
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Tokens.Ink.primary)
                    .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
            )
            .accessibilityLabel("your list, one product per line")
    }

    /// Two numbers that are not the same one. The left counts the paste, the
    /// right counts what the catalog could stand behind.
    private var counts: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("we read \(model.rawLines.count) lines")
                .eyebrow(color: Tokens.Cherry.deep)
            Spacer(minLength: 0)
            if !model.lines.isEmpty {
                EvidenceLine(
                    n: model.matchedOutrightCount,
                    of: model.lines.count,
                    label: "matched outright"
                )
            }
        }
    }

    @ViewBuilder
    private var lineList: some View {
        if let failure = model.failure {
            // Never a list of misses: a parse that did not happen says nothing
            // about whether these products exist.
            Text(failure.userMessage).meta()
        } else if model.isParsing {
            Text("reading your list…").meta()
        } else {
            VStack(spacing: 8) {
                ForEach(model.lines) { line in
                    row(line)
                }
            }
        }
    }

    private func row(_ line: ImportLine) -> some View {
        HStack(spacing: 10) {
            statusDot(line.resolution)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.text)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Tokens.Ink.primary)
                    .multilineTextAlignment(.leading)
                Text(ImportView.explanation(for: line.resolution)).meta()
            }
            Spacer(minLength: 0)
            if line.resolution == .noMatch {
                Button("fix →") { onLadder(line) }
                    .buttonStyle(.plain)
                    .font(Typography.mono(10.5))
                    .foregroundStyle(Tokens.Semantic.accentText)
                    .underline()
                    .accessibilityLabel("fix \(line.text) on the ladder")
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
        )
    }

    /// A tick for a match, a question mark for both of the others. The mark is
    /// the same because the honest distinction is in the words beside it, not
    /// in a glyph someone has to learn.
    private func statusDot(_ resolution: ImportResolution) -> some View {
        Group {
            if case .matched = resolution {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
            } else {
                Text("?").font(Typography.mono(11))
            }
        }
        .foregroundStyle(Tokens.Ink.primary)
        .frame(width: 22, height: 22)
        .background(ImportView.dotFill(resolution))
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin))
        .accessibilityHidden(true)
    }

    nonisolated static func dotFill(_ resolution: ImportResolution) -> Color {
        switch resolution {
        case .matched: Tokens.Support.mintSoft
        case .needsSize: Tokens.Support.butterSoft
        case .noMatch: Tokens.Ground.card
        }
    }

    /// What each verdict says out loud. `noMatch` names where the line is going
    /// rather than that it failed — the ladder is the plan, not the fallback.
    nonisolated static func explanation(for resolution: ImportResolution) -> String {
        switch resolution {
        case .matched: "matched in the catalog"
        case .needsSize: "matched — pick the size"
        case .noMatch: "no match — goes to the ladder"
        }
    }
}
