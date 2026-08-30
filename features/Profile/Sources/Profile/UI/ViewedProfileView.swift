import DataKit
import DesignSystem
import SwiftUI

/// Someone else's profile. GLO-125, `docs/tech/02` §3.3 and §3.5.
public struct ViewedProfileView: View {
    @State private var model: ViewedProfileModel
    @State private var reporting = false
    private let safety: SafetyActionsStore?
    private let userID: UUID?

    public init(
        store: ViewedProfileStore,
        handle: String,
        userID: UUID? = nil,
        safety: SafetyActionsStore? = nil
    ) {
        _model = State(wrappedValue: ViewedProfileModel(store: store, handle: handle, userID: userID))
        self.safety = safety
        self.userID = userID
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                if model.isLoading {
                    ProgressView().padding(.top, Tokens.Space.s8)
                } else if model.isUnavailable {
                    unavailable
                } else if let profile = model.profile {
                    header(profile)
                    followControl
                    counts(profile)
                    badges(profile)
                    surfaces
                    reportLink
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await model.load() }
        .sheet(isPresented: $reporting) {
            if let safety {
                ReportSheet(store: safety, subject: .profile, subjectUserID: userID)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Toast(message).padding(.bottom, Tokens.Space.s8)
            }
        }
    }

    /// One message for four situations, and it speculates about none of them.
    /// "Not found" and "blocked" are deliberately the same response (§1.5).
    private var unavailable: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("not here")
                .font(Typography.display(Typography.Size.h2))
                .foregroundStyle(Tokens.Ink.primary)
            Text("there's no profile at that handle.")
                .font(.system(size: Typography.Size.small))
                .foregroundStyle(Tokens.Ink.soft)
        }
    }

    /// The pop moment: whose profile this is.
    private func header(_ profile: PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("@\(profile.handle)")
                .font(Typography.display(Typography.Size.h1))
                .foregroundStyle(Tokens.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let name = profile.displayName {
                Text(name)
                    .font(.system(size: Typography.Size.body))
                    .foregroundStyle(Tokens.Ink.soft)
            }
            if let bio = profile.bio {
                Text(bio)
                    .font(.system(size: Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.primary)
            }
        }
    }

    /// Absent, not disabled, when following is not allowed. A greyed button
    /// invites "why not", and the honest answer — a block, or a minor — is one
    /// we must not give.
    @ViewBuilder private var followControl: some View {
        switch model.followState {
        case .following:
            Button("following") { Task { await model.toggleFollow() } }
                .buttonStyle(.glossed(.secondary, block: true))
        case .notFollowing:
            Button("follow") { Task { await model.toggleFollow() } }
                .buttonStyle(.glossed(.primary, block: true))
        case .unavailable:
            EmptyView()
        }
    }

    /// Only offered when there is someone to report and a store to do it with.
    @ViewBuilder private var reportLink: some View {
        if safety != nil, userID != nil {
            Button("report this profile") { reporting = true }
                .buttonStyle(.glossed(.secondary, block: true))
        }
    }

    private func counts(_ profile: PublicProfile) -> some View {
        GlossedCard {
            HStack(spacing: Tokens.Space.s6) {
                countCell(profile.followers, "followers")
                countCell(profile.following, "following")
                countCell(profile.rankedListsN, "ranked lists")
            }
        }
    }

    private func countCell(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Text("\(n)")
                .font(Typography.mono(Typography.Size.h2, bold: true))
                .foregroundStyle(Tokens.Ink.primary)
            Text(label)
                .font(.system(size: Typography.Size.meta))
                .foregroundStyle(Tokens.Ink.soft)
        }
    }

    /// Only what this person chose to publish. A nil badge is absent, not
    /// rendered as "unknown" — the difference between "did not share" and
    /// "has none" is theirs to keep.
    @ViewBuilder private func badges(_ profile: PublicProfile) -> some View {
        let shown = [profile.badgeSkinType, profile.badgeAnchor, profile.badgeHairPattern]
            .compactMap(\.self)
        if !shown.isEmpty {
            HStack(spacing: Tokens.Space.s2) {
                ForEach(shown, id: \.self) { value in
                    Badge(value, tone: .lilac)
                }
            }
        }
    }

    /// Locked surfaces are named as private rather than hidden. Hiding leaves
    /// the viewer unsure they exist; "private" is true, says nothing about the
    /// viewer, and reads the same whether the scope is `only you` or `friends`.
    private var surfaces: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("WHAT YOU CAN SEE").eyebrow()
            ForEach(model.surfaces, id: \.label) { surface in
                HStack {
                    Text(surface.label)
                        .font(.system(size: Typography.Size.body))
                        .foregroundStyle(surface.visible ? Tokens.Ink.primary : Tokens.Ink.faint)
                    Spacer()
                    if !surface.visible {
                        Text("private")
                            .font(.system(size: Typography.Size.meta))
                            .foregroundStyle(Tokens.Ink.faint)
                    }
                }
            }
        }
    }
}

/// The suggested-people card: one person, one named reason, its n.
public struct SuggestedPeopleCard: View {
    @State private var model: SuggestedPeopleModel
    private let onOpen: (SuggestedPerson) -> Void

    public init(store: ViewedProfileStore, onOpen: @escaping (SuggestedPerson) -> Void) {
        _model = State(wrappedValue: SuggestedPeopleModel(store: store))
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("PEOPLE TO FOLLOW").eyebrow()
            if model.isEmptyForGoodReason {
                Text(model.emptyLine)
                    .font(.system(size: Typography.Size.meta))
                    .foregroundStyle(Tokens.Ink.soft)
            } else {
                ForEach(model.people) { person in
                    Button { onOpen(person) } label: {
                        GlossedCard {
                            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                                Text("@\(person.handle)")
                                    .font(.system(size: Typography.Size.h3, weight: .semibold))
                                    .foregroundStyle(Tokens.Ink.primary)
                                // The reason IS the card. It is never empty — the
                                // RPC returns no row rather than a reasonless one.
                                Text(person.reason)
                                    .font(.system(size: Typography.Size.small))
                                    .foregroundStyle(Tokens.Ink.soft)
                                EvidenceLine(n: person.n, label: "ranked")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await model.load() }
    }
}
