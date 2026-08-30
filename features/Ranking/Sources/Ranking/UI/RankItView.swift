import DataKit
import DesignSystem
import SwiftUI

/// `G.FaceOff` — the whole screen behind the product page's "rank it", in the
/// frame's order: the badge, the question, the two cards, the skip, and on the
/// far side the placement.
///
/// `FaceOffView` draws the frame and has done since GLO-17. What it never had
/// was a host: something to decide *which* comparison this is, whether the
/// category is even unlocked, and where the answers go. That is this view, and
/// it is why the frame has never appeared in the app (GLO-240).
///
/// Three states the frame does not draw, because a fixture never has them:
/// loading, a category still below its unlock, and a read that failed. The
/// middle one is the interesting one — PRD §03 makes the unlock "a reward,
/// never a required step", and the leaderboard's own law is that a row which
/// cannot be ranked yet says so instead of hiding. Same law here.
public struct RankItView: View {
    @State private var model: RankSessionModel
    private let imageBase: URL?
    private let onDone: () -> Void

    public init(
        model: RankSessionModel,
        imageBase: URL? = nil,
        onDone: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.imageBase = imageBase
        self.onDone = onDone
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Space.s5) {
                switch model.state {
                case .loading:
                    ProgressView()
                        .padding(.vertical, Tokens.Space.s10)
                        .accessibilityLabel("finding your face-offs")
                case let .locked(have, need):
                    locked(have: have, need: need)
                case let .ready(session):
                    faceOff(session)
                case let .unavailable(message):
                    unavailable(message)
                }
            }
            .frame(maxWidth: .infinity)
            // 110pt of bottom room: the floating nav sits over this screen.
            .padding(.init(top: 22, leading: 0, bottom: 110, trailing: 0))
        }
        .background(Tokens.Ground.milk)
        .task { model.load() }
    }

    private func faceOff(_ session: FaceOffSession) -> some View {
        FaceOffView(
            session: session,
            contender: { FaceOffContender(id: $0, name: model.name(of: $0)) },
            saveFailure: model.saveFailure,
            onDone: onDone,
            onFinished: { model.finish($0) },
            card: { contender in
                VStack(spacing: 0) {
                    ProductImage(
                        catalog: imageURL(contender.id),
                        kind: kind(contender.id),
                        tint: ProductMock.tint(for: contender.name),
                        scale: 86
                    )
                    Text(contender.name)
                        .font(Typography.display(14, weight: 700))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Tokens.Ink.primary)
                        .padding(.top, 10)
                }
            }
        )
    }

    /// Not an apology and not a blank screen: the number you have, the number
    /// it takes, and what still works in the meantime. "like/dislike + chips
    /// only" is PRD §03's own description of the under-3 state, and both of
    /// those are built on the shelf sheet — so this promises nothing that is
    /// not already there (GLO-189).
    private func locked(have: Int, need: Int) -> some View {
        VStack(spacing: Tokens.Space.s3) {
            Badge("ranking unlocks at \(need)", tone: .lilac)
            Text("not enough to\ncompare yet")
                .font(Typography.display(27))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Tokens.Ink.primary)
            EvidenceLine(
                n: have,
                of: need,
                label: "in \(model.categoryLabel) you can rank"
            )
            Text("chips and a like still land on every one of them")
                .meta()
                .multilineTextAlignment(.center)
            Button("back to shelf", action: onDone)
                .buttonStyle(.plain)
                .font(Typography.mono(11.5))
                .foregroundStyle(Tokens.Semantic.accentText)
                .underline()
                .padding(.top, Tokens.Space.s2)
        }
        .padding(.horizontal, Tokens.Space.s4)
    }

    /// A failed read says nothing about how much you own — so it never borrows
    /// the locked state's words (the `ShadeClaim.unavailable` distinction).
    private func unavailable(_ message: String) -> some View {
        VStack(spacing: Tokens.Space.s3) {
            Text(message).meta().multilineTextAlignment(.center)
            Button("back to shelf", action: onDone)
                .buttonStyle(.plain)
                .font(Typography.mono(11.5))
                .foregroundStyle(Tokens.Semantic.accentText)
                .underline()
        }
        .padding(.horizontal, Tokens.Space.s4)
        .padding(.vertical, Tokens.Space.s8)
    }

    /// Both fall back to the drawn mock rather than a broken image, the shelf's
    /// composition rule (GLO-83): nil base or nil key degrades, never guesses.
    private func imageURL(_ itemID: UUID) -> URL? {
        guard let imageBase, let key = model.row(itemID)?.catalogImageKey else { return nil }
        return imageBase.appending(path: key)
    }

    private func kind(_ itemID: UUID) -> ProductMock.Kind {
        ProductMock.Kind.usual(forCategory: model.row(itemID)?.categorySlug ?? "")
    }
}
