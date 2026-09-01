import DataKit
import DesignSystem
import SwiftUI

/// Your own profile: a body of work, not a control panel (GLO-261).
///
/// Sean, Aug 30, after driving the merged screen: *"I don't like the add a
/// look, what a stranger sees, where else you are button in the profile. Think
/// of profile kind of like instagram profile/pinterest."* All three are gone.
/// What is left is your identity, your counts, and your things.
///
/// **`what a stranger sees` is deleted, reversing GLO-190.** The need that
/// ticket named was real — "the privacy model is correct and unverifiable" —
/// and a modal was the wrong shape for it. The answer now lives on the tab
/// strip, where every tab carries its own scope, so the question is answered
/// permanently and in place. See `ProfileScopeMark`.
///
/// `where else you are` is not deleted so much as relocated: linked socials is
/// a setting, and settings has been categorised since GLO-257.
public struct OwnProfileView: View {
    @State private var model: OwnProfileModel
    @State private var tabs: ProfileTabsModel
    @State private var viewing: SuggestedPerson?
    @State private var showingSettings = false
    @State private var claimingHandle = false
    /// The identity field `edit profile` is editing, if any (GLO-271).
    @State private var editingIdentity: ProfileIdentityField?
    private let onClaimHandle: () -> Void
    private let onOpenPrivacy: () -> Void
    private let onCompose: ((ProfileComposable) -> Void)?
    private let onOpenLook: ((UUID) -> Void)?
    private let onOpenCollection: ((UUID) -> Void)?
    private let onOpenRoutine: ((UUID) -> Void)?
    private let photoStore: ProfilePhotoStore?
    private let settingsStore: SettingsStore?
    private let handleStore: HandleStore?
    private let onSignedOut: () -> Void

    private let suggestionsStore: ViewedProfileStore
    private let safetyStore: SafetyActionsStore

    public init(
        store: OwnProfileStore,
        suggestionsStore: ViewedProfileStore,
        safetyStore: SafetyActionsStore,
        onClaimHandle: @escaping () -> Void,
        onOpenPrivacy: @escaping () -> Void,
        settingsStore: SettingsStore? = nil,
        onSignedOut: @escaping () -> Void = {},
        // Defaulted so the app layer compiles unchanged and wires each seam in
        // its own PR. Absent, a tab simply does not render — a tab in front of
        // a surface that cannot answer is the drawer's `collections land with
        // GLO-21` mistake wearing different words (GLO-189).
        looksStore: ProfileLooksStore? = nil,
        collectionsStore: ProfileCollectionsStore? = nil,
        routinesStore: ProfileRoutinesStore? = nil,
        shelfStore: ProfileShelfStore? = nil,
        // Absent, no tab carries a mark. The strip does not guess.
        scopesStore: ProfileScopesStore? = nil,
        // Absent, the empty state names what lands here and offers no `+`.
        onCompose: ((ProfileComposable) -> Void)? = nil,
        // Absent, a look tile is a card rather than a door (GLO-266).
        onOpenLook: ((UUID) -> Void)? = nil,
        // Absent, a collection/routine card is a card rather than a door
        // (GLO-272 — the click-in).
        onOpenCollection: ((UUID) -> Void)? = nil,
        onOpenRoutine: ((UUID) -> Void)? = nil,
        // Absent, the avatar is the seeded initial and carries no edit badge
        // (GLO-272's pfp door).
        photoStore: ProfilePhotoStore? = nil,
        // Absent, `onClaimHandle` is handed up as before — and GLO-239 stays
        // open. See `claimSheet`.
        handleStore: HandleStore? = nil
    ) {
        _tabs = State(
            wrappedValue: ProfileTabsModel(
                looks: looksStore, collections: collectionsStore,
                routines: routinesStore, shelf: shelfStore, scopes: scopesStore
            )
        )
        self.suggestionsStore = suggestionsStore
        self.safetyStore = safetyStore
        _model = State(wrappedValue: OwnProfileModel(store: store))
        self.onClaimHandle = onClaimHandle
        self.onOpenPrivacy = onOpenPrivacy
        self.onCompose = onCompose
        self.onOpenLook = onOpenLook
        self.onOpenCollection = onOpenCollection
        self.onOpenRoutine = onOpenRoutine
        self.photoStore = photoStore
        self.settingsStore = settingsStore
        self.handleStore = handleStore
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
                        if !tabs.tabs.isEmpty {
                            ProfileTabsSection(
                                model: tabs,
                                onCompose: onCompose,
                                // No settings store, no rows: both editors
                                // live behind it, and a control that opens
                                // nothing is the GLO-189 mistake.
                                onEditIdentity: settingsStore == nil
                                    ? nil : { editingIdentity = $0 },
                                onOpenLook: onOpenLook,
                                onOpenCollection: onOpenCollection,
                                onOpenRoutine: onOpenRoutine
                            )
                        }
                        SuggestedPeopleCard(store: suggestionsStore) { viewing = $0 }
                    }
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .task { await model.load() }
        .task { await tabs.load() }
        .renameSheet(model: tabs)
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage ?? tabs.errorMessage {
                Toast(message).padding(.bottom, Tokens.Space.s8)
            }
        }
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
        // `edit profile` opens the same two editors settings does — GLO-213
        // built them, and Sean's Aug 31 ruling asked for them here too. Two
        // doors onto one screen, not two screens.
        .sheet(item: $editingIdentity) { field in
            if let settingsStore {
                switch field {
                case .name:
                    DisplayNameView(
                        current: model.displayName,
                        save: { try await settingsStore.saveDisplayName($0) },
                        onSaved: {
                            editingIdentity = nil
                            Task { await model.load() }
                        },
                        onBack: { editingIdentity = nil }
                    )
                case .bio:
                    if let bioStore = settingsStore.bio {
                        BioView(store: bioStore, onBack: {
                            editingIdentity = nil
                            Task { await model.load() }
                        })
                    }
                }
            }
        }
        .claimSheet(isPresented: $claimingHandle, store: handleStore) {
            // **GLO-239, closed.** The claim used to be presented by the shell,
            // so nothing here knew it had happened and the profile went on
            // saying "no handle yet" over a handle that was already public.
            // Presented from this view, dismissal is a signal this view has.
            Task { await model.load() }
        }
        // A suggestion carries the user id the follow graph needs — the only
        // place a client legitimately holds one for someone else, since
        // public_profile deliberately does not return it.
        .sheet(item: $viewing) { person in
            ViewedProfileView(
                store: suggestionsStore, handle: person.handle,
                userID: person.userID, safety: safetyStore
            )
        }
    }

    /// The identity block, in Sean's order: `[avatar] display name / @handle`,
    /// then the bio.
    ///
    /// **The display name leads and the handle sits under it**, which inverts
    /// what #363 shipped. That PR made the handle the h1 on the argument that
    /// the handle is the profile's address (GLO-187) — it still is, and it is
    /// still on the identity line, one line down. Sean's sketch is explicit
    /// about the order and this is his screen. A profile with no display name
    /// promotes the handle rather than leading with a blank.
    ///
    /// What it renders is the PUBLISHED projection (`public_profile`), not your
    /// underlying facts, so an absent badge or bio here means you have
    /// published none — which is the true statement, and now the only one:
    /// there is no preview modal left to explain it at length.
    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            HStack(spacing: Tokens.Space.s3) {
                // The avatar hides from VoiceOver inside the control (the
                // same initial the name beside it already says); the edit
                // badge stays audible — it is a different fact.
                ProfileAvatarControl(name: model.avatarName, store: photoStore)
                identity
                Spacer(minLength: Tokens.Space.s2)
                // The frame's entry to settings, and the only one — settings
                // is a state of this screen, not a tab.
                IconButton("gearshape", label: "settings") { showingSettings = true }
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

    private var identity: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.leadName)
                .font(Typography.display(Typography.Size.h2))
                .foregroundStyle(model.handle == nil ? Tokens.Ink.faint : Tokens.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let under = model.handleLine {
                Text(under)
                    .font(Typography.mono(Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.soft)
                    .lineLimit(1)
            }
        }
    }

    private var claimPrompt: some View {
        GlossedCard {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text("a handle is how people find you. nothing of yours is public until you pick one.")
                    .font(.system(size: Typography.Size.body))
                    .foregroundStyle(Tokens.Ink.primary)
                Button("claim a handle") {
                    if handleStore == nil {
                        onClaimHandle()
                    } else {
                        claimingHandle = true
                    }
                }
                .buttonStyle(.glossed(.primary, block: true))
            }
        }
    }

    /// Sean's three metrics, one mono line under the identity block.
    /// See `OwnProfileModel.statLine`.
    private var counts: some View {
        Text(model.statLine).meta()
    }
}
