import DataKit
import DesignSystem
import SwiftUI

/// The privacy screen. GLO-119, `docs/tech/02` §1.
///
/// Built from the design system rather than a frame (Sean, Aug 29: no frames
/// for 1.5). The kit's two privacy frames are reference only, and their missing
/// `discoverable` row is superseded — that control ships as designed in §1.2.
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
                Text(row.title)
                    .font(.system(size: Typography.Size.h3, weight: .semibold))
                    .foregroundStyle(Tokens.Ink.primary)
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
