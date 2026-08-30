import DesignSystem
import SwiftUI

/// Settings. GLO-213, built to `G.Profile`'s settings sub-state.
///
/// There is no `G.Settings` in the kit — settings is a state of the profile
/// frame, reached by the gear in its header, which is why it read as missing
/// rather than unbuilt.
public struct SettingsView: View {
    @State private var model: SettingsModel
    @State private var confirmingSignOut = false
    @State private var editingName = false
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
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Button("← back", action: onBack)
                    .buttonStyle(.plain)
                    .font(Typography.mono(Typography.Size.meta))
                    .foregroundStyle(Tokens.Cherry.deep)

                Text("settings")
                    .font(Typography.display(Typography.Size.h2))
                    .foregroundStyle(Tokens.Ink.primary)

                if model.isLoading {
                    ProgressView().padding(.top, Tokens.Space.s6)
                } else {
                    factsCard
                    privacyRow
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

    /// One card, rows divided by a hairline, exactly as the frame draws it.
    private var factsCard: some View {
        GlossedCard {
            VStack(spacing: 0) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().overlay(Tokens.Ground.line)
                    }
                    factRow(row)
                }
                Divider().overlay(Tokens.Ground.line)
                signOutRow
            }
        }
    }

    /// The name row opens an editor; every other row states a fact set
    /// elsewhere (onboarding, the tune sheet, the shelf). Only the ones that
    /// can be changed here are tappable.
    @ViewBuilder private func factRow(_ row: SettingsRow) -> some View {
        if row.id == "name" {
            Button { editingName = true } label: {
                factRowBody(row, opensSomething: true)
            }
            .buttonStyle(.plain)
        } else {
            factRowBody(row, opensSomething: false)
        }
    }

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
            if opensSomething {
                Image(systemName: "chevron.right")
                    .font(Typography.control(11))
                    .foregroundStyle(Tokens.Ink.faint)
            }
        }
        .padding(.vertical, Tokens.Space.s3)
        .contentShape(Rectangle())
    }

    /// Cherry, per the frame — the one row that ends something.
    private var signOutRow: some View {
        Button { confirmingSignOut = true } label: {
            HStack {
                Text("sign out")
                    .font(Typography.display(Typography.Size.small, weight: 700))
                    .foregroundStyle(Tokens.Cherry.deep)
                Spacer()
            }
            .padding(.vertical, Tokens.Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Its own card in the frame, and it earns that: it is the only row that
    /// opens a screen rather than stating a fact.
    private var privacyRow: some View {
        Button(action: onOpenPrivacy) {
            GlossedCard {
                HStack(spacing: Tokens.Space.s3) {
                    VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                        Text("privacy")
                            .font(Typography.display(Typography.Size.small, weight: 700))
                            .foregroundStyle(Tokens.Ink.primary)
                        Text("who can see your surfaces, and what you show")
                            .meta()
                    }
                    Spacer(minLength: Tokens.Space.s2)
                    Image(systemName: "chevron.right")
                        .font(Typography.control(12))
                        .foregroundStyle(Tokens.Ink.soft)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
