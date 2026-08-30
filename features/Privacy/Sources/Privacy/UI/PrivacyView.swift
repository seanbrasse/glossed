import DataKit
import DesignSystem
import SwiftUI

/// The privacy screen. GLO-119, `docs/tech/02` §1.
///
/// Structured to the kit's `G.Privacy` frame (Sean, Aug 30: "make sure the
/// switches match what we have in our designs") — master card, four rows, a
/// scope dot each, built from design-system primitives.
///
/// Three deliberate departures from the frame: the `discoverable` card, which
/// the frame lacks and §1.2 supersedes it on; `only you` rather than the
/// frame's `just you` (Sean's rename, Aug 29); and no trailing `save` button,
/// because every change here writes immediately and a save button on a saved
/// screen misdescribes what a tap did.
public struct PrivacyView: View {
    @State private var model: PrivacyModel

    public init(store: PrivacyStore) {
        _model = State(wrappedValue: PrivacyModel(store: store))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                header
                if model.isLoading {
                    ProgressView().padding(.top, Tokens.Space.s8)
                } else {
                    everythingCard
                    Text("OR ONE AT A TIME").eyebrow()
                    ForEach(PrivacyRow.allCases, id: \.self) { row in
                        scopeCard(row)
                    }
                    discoverableCard
                    footnote
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await model.load() }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Toast(message).padding(.bottom, Tokens.Space.s8)
            }
        }
    }

    /// The one pop moment: the summary, and nothing else on the screen competes.
    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("PRIVACY").eyebrow()
            Text(model.summaryLine)
                .font(Typography.display(Typography.Size.h1))
                .foregroundStyle(Tokens.Ink.primary)
            Text(summaryDetail)
                .font(.system(size: Typography.Size.small))
                .foregroundStyle(Tokens.Ink.soft)
            // The frame's aside, minus its trailing ✿ — that glyph is not in
            // Caveat, so it never draws (GLO-69).
            Text("three scopes, four things, one switch for all of it")
                .handAside()
                .rotationEffect(Tokens.Rotate.r3)
        }
    }

    /// The frame's headline: one control that moves all four at once. Without
    /// it the screen states "mixed" but offers no way to un-mix.
    private var everythingCard: some View {
        GlossedCard(tint: .butter) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                HStack(spacing: Tokens.Space.s2) {
                    Text("everything")
                        .font(Typography.display(Typography.Size.h3, weight: 800))
                        .foregroundStyle(Tokens.Ink.primary)
                    Spacer(minLength: Tokens.Space.s2)
                    if let overall = model.scopes.overallScope {
                        Badge("all four · \(overall.label)", tone: .mint)
                    } else {
                        Badge("mixed", tone: .lilac)
                    }
                }

                Segmented(
                    options: PrivacyScope.allCases.map(\.label),
                    selection: Binding(
                        get: { model.scopes.overallScope?.label ?? "" },
                        set: { label in
                            guard let scope = PrivacyScope.allCases.first(where: { $0.label == label })
                            else { return }
                            Task { await model.setAll(to: scope) }
                        }
                    )
                )
                .disabled(model.isLockedByAgeGate)

                Text(model.scopes.overallScope == nil
                    ? "set each one below, or tap a scope here to move all four at once."
                    : "one tap moves all four. change any single one below and this reads mixed.")
                    .font(.system(size: Typography.Size.meta))
                    .foregroundStyle(Tokens.Ink.soft)
            }
        }
    }

    /// The frame's scope dot: current state legible without reading the
    /// control under it.
    private func scopeDot(_ scope: PrivacyScope) -> some View {
        Circle()
            .fill(dotFill(scope))
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair))
            .accessibilityHidden(true)
    }

    private func dotFill(_ scope: PrivacyScope) -> Color {
        switch scope {
        case .onlyYou: Tokens.Support.mintSoft
        case .friends: Tokens.Support.lilacSoft
        case .publicScope: Tokens.Support.butterSoft
        }
    }

    /// Stated rather than rounded. "mixed" is the honest answer when the rows
    /// disagree, and the line underneath says what to do about it.
    private var summaryDetail: String {
        model.scopes.overallScope == nil
            ? "your surfaces are set differently. each row below decides its own."
            : "every surface below is set to \(model.summaryLine)."
    }

    private func scopeCard(_ row: PrivacyRow) -> some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                HStack(spacing: Tokens.Space.s2) {
                    Text(row.title)
                        .font(.system(size: Typography.Size.h3, weight: .semibold))
                        .foregroundStyle(Tokens.Ink.primary)
                    Spacer(minLength: Tokens.Space.s2)
                    scopeDot(model.scopes.scope(for: row.surface))
                }
                Text(row.detail)
                    .font(.system(size: Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.soft)

                Segmented(
                    options: PrivacyScope.allCases.map(\.label),
                    selection: Binding(
                        get: { model.scopes.scope(for: row.surface).label },
                        set: { label in
                            guard let scope = PrivacyScope.allCases.first(where: { $0.label == label }),
                                  scope != model.scopes.scope(for: row.surface)
                            else { return }
                            Task { await model.setScope(row, to: scope) }
                        }
                    )
                )
                .disabled(model.isLockedByAgeGate)

                Text(model.scopes.scope(for: row.surface).explanation)
                    .font(.system(size: Typography.Size.meta))
                    .foregroundStyle(Tokens.Ink.faint)
            }
        }
    }

    /// Its own card, deliberately apart from the four scopes. Being visible and
    /// wanting to be surfaced are different decisions (§1.3), and putting this
    /// switch among the scope rows would read as a fifth scope.
    private var discoverableCard: some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                GlossedSwitch(
                    isOn: Binding(
                        get: { model.scopes.discoverable },
                        set: { on in Task { await model.setDiscoverable(on) } }
                    ),
                    label: "let people find you"
                )
                .disabled(model.isLockedByAgeGate)

                Text(model.discoverableDetail)
                    .font(.system(size: Typography.Size.meta))
                    .foregroundStyle(Tokens.Ink.faint)
            }
        }
    }

    /// The minor lock, stated only when it applies. Saying "you're restricted"
    /// to every user would be noise; saying nothing to a locked one would leave
    /// them tapping a control that silently refuses.
    @ViewBuilder private var footnote: some View {
        if model.isLockedByAgeGate {
            Text("your account is private while you're under 18. this isn't something you can change.")
                .font(.system(size: Typography.Size.meta))
                .foregroundStyle(Tokens.Ink.soft)
                .padding(.horizontal, Tokens.Space.s2)
        }
    }
}
