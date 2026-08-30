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
    @State private var previewing = false
    private let onClaimHandle: () -> Void
    private let onOpenPrivacy: () -> Void

    private let suggestionsStore: ViewedProfileStore
    private let safetyStore: SafetyActionsStore
    private let socialsStore: LinkedSocialsStore
    private let previewStore: StrangerPreviewStore

    public init(
        store: OwnProfileStore,
        suggestionsStore: ViewedProfileStore,
        safetyStore: SafetyActionsStore,
        socialsStore: LinkedSocialsStore,
        previewStore: StrangerPreviewStore,
        onClaimHandle: @escaping () -> Void,
        onOpenPrivacy: @escaping () -> Void
    ) {
        self.suggestionsStore = suggestionsStore
        self.safetyStore = safetyStore
        self.socialsStore = socialsStore
        self.previewStore = previewStore
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
                        SuggestedPeopleCard(store: suggestionsStore) { viewing = $0 }
                        previewLink
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
        .sheet(isPresented: $previewing) {
            StrangerPreviewView(store: previewStore)
        }
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
            HStack(spacing: Tokens.Space.s3) {
                // Hidden from VoiceOver: it is the same initial the handle
                // beside it already says, and announcing "m" then "@maya_k"
                // reads as two facts when it is one.
                Avatar(name: model.handle ?? "?", size: 52)
                    .accessibilityHidden(true)
                Text(model.handle.map { "@\($0)" } ?? "no handle yet")
                    .font(Typography.display(Typography.Size.h1))
                    .foregroundStyle(model.handle == nil ? Tokens.Ink.faint : Tokens.Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if model.profileUnreachable {
                Badge("profile not loading", tone: .lilac)
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
                    countCell(model.followersN, "follower", "followers")
                    countCell(model.followingN, "following", "following")
                    countCell(model.rankedListsN, "ranked list", "ranked lists")
                }
                EvidenceLine(n: model.profile?.shelfN ?? 0, label: "on your shelf")
            }
        }
    }

    /// Privacy lives one tap away rather than inline: these badges publish
    /// specific facts, while the scopes decide who sees the surfaces at all.
    /// Mixing them on one screen would blur two different questions.
    /// The privacy model is correct and invisible; this is where a user can
    /// check it rather than trust the copy (GLO-190).
    private var previewLink: some View {
        Button("what a stranger sees", action: { previewing = true })
            .buttonStyle(.glossed(.primary, block: true))
    }

    private var socialsLink: some View {
        Button("where else you are", action: { editingSocials = true })
            .buttonStyle(.glossed(.secondary, block: true))
    }

    private var privacyLink: some View {
        Button("who can see your surfaces", action: onOpenPrivacy)
            .buttonStyle(.glossed(.secondary, block: true))
    }

    private func countCell(_ n: Int, _ one: String, _ many: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Text("\(n)")
                .font(Typography.mono(Typography.Size.h2, bold: true))
                .foregroundStyle(Tokens.Ink.primary)
            Text(n == 1 ? one : many)
                .font(.system(size: Typography.Size.meta))
                .foregroundStyle(Tokens.Ink.soft)
        }
    }
}
