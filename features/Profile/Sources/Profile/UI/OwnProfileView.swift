import DataKit
import DesignSystem
import SwiftUI

/// Your own profile. GLO-124, `docs/tech/02` §3.3–§3.4.
///
/// Built from the design system (Sean, Aug 29: no frames for 1.5).
public struct OwnProfileView: View {
    @State private var model: OwnProfileModel
    @State private var viewing: SuggestedPerson?
    @State private var editingSocials = false
    private let onClaimHandle: () -> Void
    private let onOpenPrivacy: () -> Void

    private let suggestionsStore: ViewedProfileStore
    private let safetyStore: SafetyActionsStore
    private let socialsStore: LinkedSocialsStore

    public init(
        store: OwnProfileStore,
        suggestionsStore: ViewedProfileStore,
        safetyStore: SafetyActionsStore,
        socialsStore: LinkedSocialsStore,
        onClaimHandle: @escaping () -> Void,
        onOpenPrivacy: @escaping () -> Void
    ) {
        self.suggestionsStore = suggestionsStore
        self.safetyStore = safetyStore
        self.socialsStore = socialsStore
        _model = State(wrappedValue: OwnProfileModel(store: store))
        self.onClaimHandle = onClaimHandle
        self.onOpenPrivacy = onOpenPrivacy
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                if model.isLoading {
                    ProgressView().padding(.top, Tokens.Space.s8)
                } else {
                    header
                    if model.needsHandle {
                        claimPrompt
                    } else {
                        counts
                        badgeSection
                        SuggestedPeopleCard(store: suggestionsStore) { viewing = $0 }
                        socialsLink
                        privacyLink
                    }
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
        // A suggestion carries the user id the follow graph needs — the only
        // place a client legitimately holds one for someone else, since
        // public_profile deliberately does not return it.
        .sheet(isPresented: $editingSocials) {
            LinkedSocialsView(store: socialsStore)
        }
        .sheet(item: $viewing) { person in
            ViewedProfileView(
                store: suggestionsStore, handle: person.handle,
                userID: person.userID, safety: safetyStore
            )
        }
    }

    /// The pop moment: the handle.
    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("YOU").eyebrow()
            Text(model.handle.map { "@\($0)" } ?? "no handle yet")
                .font(Typography.display(Typography.Size.h1))
                .foregroundStyle(model.handle == nil ? Tokens.Ink.faint : Tokens.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if model.handleAwaitingReview {
                Badge("waiting to be reviewed", tone: .lilac)
            }
        }
    }

    private var claimPrompt: some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text("a handle is how people find you. nothing of yours is public until you pick one.")
                    .font(.system(size: Typography.Size.body))
                    .foregroundStyle(Tokens.Ink.primary)
                Button("claim a handle", action: onClaimHandle)
                    .buttonStyle(.glossed(.primary, block: true))
            }
        }
    }

    /// Every count in mono, and the shelf count as an explicit claim with its
    /// n. Zero is shown, not hidden — a claim that vanishes when it is
    /// unflattering is not evidence.
    private var counts: some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                HStack(spacing: Tokens.Space.s6) {
                    countCell(model.followersN, "followers")
                    countCell(model.followingN, "following")
                    countCell(model.rankedListsN, "ranked lists")
                }
                EvidenceLine(n: model.profile?.shelfN ?? 0, label: "on your shelf")
            }
        }
    }

    /// Privacy lives one tap away rather than inline: these badges publish
    /// specific facts, while the scopes decide who sees the surfaces at all.
    /// Mixing them on one screen would blur two different questions.
    private var socialsLink: some View {
        Button("where else you are", action: { editingSocials = true })
            .buttonStyle(.glossed(.secondary, block: true))
    }

    private var privacyLink: some View {
        Button("who can see your surfaces", action: onOpenPrivacy)
            .buttonStyle(.glossed(.secondary, block: true))
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

    /// Each switch says what it publishes BEFORE it is flipped. These three are
    /// the only path by which skin type, the anchor shade and hair pattern
    /// reach another person (§3.4), so the consequence belongs next to the
    /// control rather than in a policy.
    private var badgeSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("WHAT YOU SHOW").eyebrow()
            ForEach(BadgeRow.all) { row in
                GlossedCard {
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        GlossedSwitch(
                            isOn: Binding(
                                get: { model.badges.isOn(row.badge) },
                                set: { on in Task { await model.setBadge(row.badge, on: on) } }
                            ),
                            label: row.title
                        )
                        Text(row.detail)
                            .font(.system(size: Typography.Size.meta))
                            .foregroundStyle(Tokens.Ink.faint)
                    }
                }
            }
            Text("all three are off until you turn them on.")
                .font(.system(size: Typography.Size.meta))
                .foregroundStyle(Tokens.Ink.soft)
                .padding(.horizontal, Tokens.Space.s2)
        }
    }
}
