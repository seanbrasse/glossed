import DesignSystem
import SwiftUI

/// Settings. GLO-213, built to `G.Profile`'s settings sub-state.
///
/// There is no `G.Settings` in the kit — settings is a state of the profile
/// frame, reached by the gear in its header, which is why it read as missing
/// rather than unbuilt.
public struct SettingsView: View {
    @State private var model: SettingsModel
    @State private var path = NavigationPath()
    @State private var confirmingSignOut = false
    @State private var editingName = false
    @State private var editingBio = false
    private let onOpenPrivacy: () -> Void
    private let onSignedOut: () -> Void
    private let onBack: () -> Void

    public init(
        store: SettingsStore,
        onOpenPrivacy: @escaping () -> Void,
        onSignedOut: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        _model = State(wrappedValue: SettingsModel(store: store))
        self.onOpenPrivacy = onOpenPrivacy
        self.onSignedOut = onSignedOut
        self.onBack = onBack
    }

    public var body: some View {
        NavigationStack(path: $path) {
            root
                // A push rather than a state swap, so going back returns to
                // the root exactly as it was — GLO-257 asks for that in as
                // many words, and a swapped `@State` loses the scroller.
                .navigationDestination(for: SettingsCategory.self, destination: categoryScreen)
                .hidingNavigationChrome()
        }
        .task { await model.load() }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Toast(message).padding(.bottom, Tokens.Space.s8)
            }
        }
        .sheet(isPresented: $editingName) {
            DisplayNameView(
                current: model.displayName,
                save: { try await model.store.saveDisplayName($0) },
                onSaved: {
                    editingName = false
                    Task { await model.reload() }
                },
                onBack: { editingName = false }
            )
        }
        .sheet(isPresented: $editingBio) {
            if let bioStore = model.store.bio {
                BioView(store: bioStore, onBack: {
                    editingBio = false
                    Task { await model.reload() }
                })
            }
        }
        .confirmationDialog("sign out?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("sign out", role: .destructive) {
                Task {
                    if await model.signOut() {
                        onSignedOut()
                    }
                }
            }
            Button("stay signed in", role: .cancel) {}
        } message: {
            Text("your shelf stays where it is — you'll need your email to get back in.")
        }
    }

    /// The root: three ways in and a sign-out, and nothing else.
    ///
    /// **Sean's ruling, and a deliberate divergence from `G.Profile`**, whose
    /// settings state is one bordered card of seven flat rows: *"categories the
    /// user clicks into, so settings looks less busy at first glance."* A later
    /// conformance audit should read `SettingsCategory`'s doc before restoring
    /// the flat list.
    private var root: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                backButton("← back", action: onBack)
                Text("settings")
                    .font(Typography.display(Typography.Size.h2))
                    .foregroundStyle(Tokens.Ink.primary)
                if model.isLoading {
                    ProgressView().padding(.top, Tokens.Space.s6)
                } else {
                    ForEach(model.categories) { categoryCard($0) }
                    privacyRow
                    signOutCard
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
    }

    private func categoryCard(_ category: SettingsCategory) -> some View {
        NavigationLink(value: category) {
            GlossedCard {
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text(category.label)
                        .font(Typography.display(Typography.Size.small, weight: 700))
                        .foregroundStyle(Tokens.Ink.primary)
                    // What is inside, in the app's own voice. The preview IS
                    // the affordance — there is no chevron, because the kit
                    // ships `ICONS.chevronRight` and DesignSystem has not
                    // ported it, and reaching for `Image(systemName:)` is
                    // GLO-64 exactly.
                    Text(category.summary).meta()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.label), \(category.summary)")
    }

    /// One category's rows, one card, divided by hairlines — the frame's own
    /// card, just holding fewer rows than it used to.
    private func categoryScreen(_ category: SettingsCategory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                backButton("← settings") { path.removeLast(path.count) }
                Text(category.label)
                    .font(Typography.display(Typography.Size.h2))
                    .foregroundStyle(Tokens.Ink.primary)
                GlossedCard {
                    VStack(spacing: 0) {
                        ForEach(Array(category.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                Divider().overlay(Tokens.Ground.line)
                            }
                            factRow(row)
                        }
                    }
                }
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .hidingNavigationChrome()
    }

    private func backButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(Typography.mono(Typography.Size.meta))
            .foregroundStyle(Tokens.Cherry.deep)
    }

    /// Only `row.isEditable` opens anything. Every other row states a fact set
    /// elsewhere — onboarding, the tune sheet, the shelf — and **the birthday
    /// states one that is set nowhere at all** (GLO-257): it is the 18+ gate,
    /// and a gate the gated party can edit is not a gate. It renders with no
    /// affordance, not a disabled one, and no copy about appealing it.
    @ViewBuilder private func factRow(_ row: SettingsRow) -> some View {
        if row.isEditable {
            Button { open(row) } label: {
                factRowBody(row, opensSomething: true)
            }
            .buttonStyle(.plain)
        } else {
            factRowBody(row, opensSomething: false)
        }
    }

    private func open(_ row: SettingsRow) {
        switch row.id {
        case "name": editingName = true
        case "bio": editingBio = true
        default: break
        }
    }

    /// `opensSomething` no longer draws a chevron: the two `Image(systemName:
    /// "chevron.right")` that used to sit here and on the privacy card were
    /// SF Symbols, which GLO-64 is open about and which GLO-257 names as a
    /// constraint. It now sets the trait instead, so the row still announces
    /// as a button without a glyph the kit does not own.
    private func factRowBody(_ row: SettingsRow, opensSomething: Bool) -> some View {
        HStack(spacing: Tokens.Space.s3) {
            Text(row.label)
                .font(Typography.display(Typography.Size.small, weight: 700))
                .foregroundStyle(Tokens.Ink.primary)
            Spacer(minLength: Tokens.Space.s2)
            // Never the frame's fixture value. An unanswered fact says so.
            Text(row.value ?? "not set yet")
                .meta(color: row.value == nil ? Tokens.Ink.faint : Tokens.Ink.soft)
                .multilineTextAlignment(.trailing)
                // A bio is sentences; the row is a row. Two lines, then an
                // ellipsis — the editor shows the whole thing.
                .lineLimit(2)
        }
        .padding(.vertical, Tokens.Space.s3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(opensSomething ? [.isButton] : [])
    }

    /// Cherry, per the frame — the one row that ends something. It stays at the
    /// root rather than moving into a category: signing out is not a detail
    /// about you, and burying it would be its own kind of dark pattern.
    private var signOutCard: some View {
        Button { confirmingSignOut = true } label: {
            GlossedCard {
                HStack {
                    Text("sign out")
                        .font(Typography.display(Typography.Size.small, weight: 700))
                        .foregroundStyle(Tokens.Cherry.deep)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Its own card in the frame, and it earns that: it is the only row that
    /// opens a screen rather than stating a fact. It is not a
    /// `NavigationLink` because the screen belongs to another feature and the
    /// shell presents it — settings closes first.
    private var privacyRow: some View {
        Button(action: onOpenPrivacy) {
            GlossedCard {
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text("privacy")
                        .font(Typography.display(Typography.Size.small, weight: 700))
                        .foregroundStyle(Tokens.Ink.primary)
                    Text("who can see your surfaces, and what you show")
                        .meta()
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    /// Both screens draw the frame's own `← back` in mono cherry, so the
    /// platform's bar and its back button would be a second one. iOS-only:
    /// the package also builds for macOS so tests run without a simulator,
    /// and neither modifier exists there.
    func hidingNavigationChrome() -> some View {
        #if os(iOS)
            return toolbar(.hidden, for: .navigationBar).navigationBarBackButtonHidden(true)
        #else
            return self
        #endif
    }
}
