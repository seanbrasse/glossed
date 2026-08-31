import DataKit
import DesignSystem
import SwiftUI

/// The handle step. **Nobody reaches the app without one** — Sean, Aug 31:
/// *"Users shouldn't make it through onboarding without a username/handle."*
///
/// So there is no skip and no "later". A handle is the profile's address
/// (GLO-187); without one `OwnProfileView` renders "no handle yet" over its own
/// identity block and nothing of yours can be found.
///
/// **The suggestion is derived from the name and is only a suggestion.** Asked
/// whether to auto-assign one, the answer here is no: an auto-assigned handle
/// means collisions resolved into `maya_k_4821`, which hands someone an
/// identity they did not choose on the one field the product calls "how people
/// find you". Pre-filling it costs the user one tap if they like it and nothing
/// if they don't.
///
/// This is `features/Profile`'s `HandleClaimView` in shape but not in code:
/// features never import features, and the seam below is what the app fills.
public struct OnbHandleView: View {
    @State private var model: OnbHandleModel
    private let onClaimed: () -> Void

    public init(model: OnbHandleModel, onClaimed: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onClaimed = onClaimed
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Text("LAST ONE · YOUR HANDLE").eyebrow()
                    Text("pick your\nhandle")
                        .font(Typography.display(32))
                        .tracking(-0.64)
                        .foregroundStyle(Tokens.Ink.primary)
                    Text("this is how people find you.")
                        .font(Typography.hand())
                        .foregroundStyle(Tokens.Semantic.accentText)
                    GlossedInput(
                        "yourname",
                        text: Binding(get: { model.typed }, set: { model.typing($0) }),
                        label: "handle"
                    )
                    verdictLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(.init(top: 18, leading: 22, bottom: 22, trailing: 22))
        .background(Tokens.Ground.milk)
        .task { model.suggest() }
    }

    /// What the field can say. Availability is the server's answer, so the
    /// line waits rather than guessing — an optimistic "available" that the
    /// claim then refuses is worse than a beat of silence.
    @ViewBuilder private var verdictLine: some View {
        switch model.verdict {
        case .empty:
            Text("letters, numbers, dots and underscores.").meta()
        case .malformed:
            Text("letters, numbers, dots and underscores — nothing else.").meta()
        case .checking:
            Text("checking…").meta()
        case .taken:
            Text("taken. try another.").meta()
        case .available:
            Badge("available", tone: .mint)
        case let .failed(message):
            Text(message).meta()
        }
    }

    private var footer: some View {
        VStack(spacing: Tokens.Space.s2) {
            Button(model.isClaiming ? "claiming…" : "claim it") {
                model.claim(onClaimed: onClaimed)
            }
            .buttonStyle(.glossed(block: true))
            .disabled(!model.canClaim || model.isClaiming)
            // No skip. See the type comment.
            //
            // **And no promise about changing it.** The first draft of this
            // line said "you can change it later in settings" — which is false
            // until GLO-270 builds the rename path: `claim_handle` has no
            // rename branch and `handles` carries no UPDATE policy at all. The
            // profile's own claim screen currently says the opposite ("you
            // can't change it later"), and two screens disagreeing about the
            // same fact is worse than neither mentioning it. GLO-270 owns both
            // strings, in the PR that makes one of them true.
            Text("your shelf is next.")
                .meta()
                .frame(maxWidth: .infinity)
        }
        .padding(.top, Tokens.Space.s3)
    }
}
