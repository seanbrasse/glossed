import DataKit
import DesignSystem
import SwiftUI

/// Your own profile. GLO-124, `docs/tech/02` §3.3–§3.4.
///
/// Built from the design system (Sean, Aug 29: no frames for 1.5).
public struct OwnProfileView: View {
    @State private var model: OwnProfileModel
    @State private var tabs: ProfileTabsModel
    @State private var viewing: SuggestedPerson?
    @State private var editingSocials = false
    @State private var previewing = false
    @State private var showingSettings = false
    private let onClaimHandle: () -> Void
    private let onCreateLook: (() -> Void)?
    private let onOpenPrivacy: () -> Void
    private let settingsStore: SettingsStore?
    private let onSignedOut: () -> Void

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
        onOpenPrivacy: @escaping () -> Void,
        settingsStore: SettingsStore? = nil,
        onSignedOut: @escaping () -> Void = {},
        // Defaulted so the app layer compiles unchanged and wires the seam in
        // its own PR (GLO-230). Absent, the segmented control and the tabs
        // below it simply do not render — the frame's lower half is missing
        // rather than pretending to be empty, which is the only honest thing a
        // screen with no read can do.
        routinesStore: ProfileRoutinesStore? = nil,
        collectionsStore: ProfileCollectionsStore? = nil,
        // GLO-254. `features/Profile` may not import `features/Looks`, so the
        // composer arrives as a callback the app layer fills. Nil means this
        // build has no looks composer and the button is absent — not present
        // and inert.
        onCreateLook: (() -> Void)? = nil
    ) {
        _tabs = State(
            wrappedValue: ProfileTabsModel(routines: routinesStore, collections: collectionsStore)
        )
        self.suggestionsStore = suggestionsStore
        self.safetyStore = safetyStore
        self.socialsStore = socialsStore
        self.previewStore = previewStore
        _model = State(wrappedValue: OwnProfileModel(store: store))
        self.onClaimHandle = onClaimHandle
        self.onCreateLook = onCreateLook
        self.onOpenPrivacy = onOpenPrivacy
        self.settingsStore = settingsStore
        self.onSignedOut = onSignedOut
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
                        // The frame's order: the segmented control and its
                        // tab sit directly under the stat line, above
                        // everything the profile grew afterwards.
                        if !tabs.tabs.isEmpty {
                            ProfileTabsSection(model: tabs)
                        }
                        SuggestedPeopleCard(store: suggestionsStore) { viewing = $0 }
                        createLookLink
                        previewLink
                        socialsLink
                    }
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await model.load() }
        .task { await tabs.load() }
        // A presented sheet rather than an in-view overlay: the floating nav
        // is above this tab's content and covered the overlay's `save`. See
        // `renameSheet`.
        .renameSheet(model: tabs)
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Toast(message).padding(.bottom, Tokens.Space.s8)
            }
        }
        // A suggestion carries the user id the follow graph needs — the only
        // place a client legitimately holds one for someone else, since
        // public_profile deliberately does not return it.
        .sheet(isPresented: $showingSettings) {
            if let settingsStore {
                SettingsView(
                    store: settingsStore,
                    // Settings closes first: privacy is another feature's
                    // screen and the shell presents it, so handing it up
                    // through a sheet that is still open stacks two.
                    onOpenPrivacy: { showingSettings = false; onOpenPrivacy() },
                    onSignedOut: { showingSettings = false; onSignedOut() },
                    onBack: { showingSettings = false }
                )
            }
        }
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
    ///
    /// `G.Profile` makes the DISPLAY NAME the h1 and shows no handle at all,
    /// because the frame predates handles entirely — V1 had no public
    /// identity to address. GLO-187 made the handle the profile's address, and
    /// #363 settled the governing principle for this screen: your own profile
    /// shows the identity everyone else sees, or you become the only person
    /// looking at a different one. So the identity block below is
    /// `ViewedProfileView`'s, element for element — handle, name, badges,
    /// bio — and the frame's ordering is deliberately not followed.
    ///
    /// What it renders is the PUBLISHED projection (`public_profile`), not
    /// your underlying facts, so an absent badge or bio here means you have
    /// published none — which is the true statement, and the one "what a
    /// stranger sees" then explains at length.
    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("YOU").eyebrow()
            HStack(spacing: Tokens.Space.s3) {
                // Hidden from VoiceOver: it is the same initial the handle
                // beside it already says, and announcing "m" then "@maya_k"
                // reads as two facts when it is one.
                Avatar(name: model.avatarName, size: 52)
                    .accessibilityHidden(true)
                Text(model.handle.map { "@\($0)" } ?? "no handle yet")
                    .font(Typography.display(Typography.Size.h1))
                    .foregroundStyle(model.handle == nil ? Tokens.Ink.faint : Tokens.Ink.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: Tokens.Space.s2)
                // The frame's entry to settings, and the only one — settings
                // is a state of this screen, not a tab.
                IconButton("gearshape", label: "settings") { showingSettings = true }
            }
            if let name = model.displayName {
                Text(name)
                    .font(.system(size: Typography.Size.body))
                    .foregroundStyle(Tokens.Ink.soft)
            }
            ProfileBadgeRow(
                skinType: model.profile?.badgeSkinType,
                anchor: model.profile?.badgeAnchor,
                hairPattern: model.profile?.badgeHairPattern
            )
            if let bio = model.bio {
                Text(bio)
                    .font(.system(size: Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.profileUnreachable {
                Badge("profile not loading", tone: .lilac)
            }
        }
    }

    /// The profile's half of GLO-254 — Sean, asked where looks are created:
    /// *"Should be here and in the profile tab?"*, ruled yes, both. The `+`
    /// drawer is the other half and belongs to the shell.
    ///
    /// Secondary, not primary: `what a stranger sees` below it is this
    /// screen's one pop moment, and two shouting buttons read as none.
    ///
    /// The copy says `add a look` and stops. It does not say who will see it —
    /// `looks.state` is not the client's to set (GLO-238) and V1 shows nothing
    /// of yours to anyone, so a button promising an audience would be GLO-189
    /// with a photo attached.
    @ViewBuilder private var createLookLink: some View {
        if let onCreateLook {
            Button("add a look", action: onCreateLook)
                .buttonStyle(.glossed(.secondary, block: true))
        }
    }

    private var previewLink: some View {
        Button("what a stranger sees", action: { previewing = true })
            .buttonStyle(.glossed(.primary, block: true))
    }

    private var socialsLink: some View {
        Button("where else you are", action: { editingSocials = true })
            .buttonStyle(.glossed(.secondary, block: true))
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

    /// The frame's stat line: one row of mono counts under the bio, not a card
    /// of cells. See `OwnProfileModel.statLine` for what each part is and why
    /// the frame's third clause is absent.
    private var counts: some View {
        Text(model.statLine).meta()
    }
}
