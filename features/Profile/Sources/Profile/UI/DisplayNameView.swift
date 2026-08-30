import DataKit
import DesignSystem
import SwiftUI

/// Setting the name a stranger sees. GLO-204.
///
/// No kit frame — `G.Profile` renders a display name but never offers to edit
/// one, so this is built from the design system under Sean's Aug 29 ruling.
///
/// **Clearing a name is deliberately not offered.** `saveProfile` upserts the
/// whole row and a nil `displayName` is *omitted* from the payload, so nil
/// leaves the old value standing — clearing would have to store `""`. An empty
/// string is present-but-meaningless: `ViewedProfileView` renders
/// `if let name`, so a cleared name would show as a blank byline rather than
/// falling back to the handle. That is the same present-but-semantically-absent
/// shape as GLO-212's badges, and offering a broken clear is worse than not
/// offering one.
struct DisplayNameView: View {
    @State private var typed: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let save: (String) async throws -> Void
    private let onSaved: () -> Void
    private let onBack: () -> Void

    init(
        current: String?,
        save: @escaping (String) async throws -> Void,
        onSaved: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        _typed = State(initialValue: current ?? "")
        self.save = save
        self.onSaved = onSaved
        self.onBack = onBack
    }

    private var trimmed: String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmed.isEmpty && !isSaving
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Button("← back", action: onBack)
                    .buttonStyle(.plain)
                    .font(Typography.mono(Typography.Size.meta))
                    .foregroundStyle(Tokens.Cherry.deep)

                Text("your name")
                    .font(Typography.display(Typography.Size.h2))
                    .foregroundStyle(Tokens.Ink.primary)

                // Says who sees it before it is typed, not after — the rule the
                // badge switches follow, for the same reason.
                Text("shown on your profile beside your handle. anyone who can see your profile sees it.")
                    .font(.system(size: Typography.Size.small))
                    .foregroundStyle(Tokens.Ink.soft)
                    .fixedSize(horizontal: false, vertical: true)

                nameField

                Button("save") {
                    Task { await performSave() }
                }
                .buttonStyle(.glossed(.primary, block: true))
                .disabled(!canSave)

                Text("a name can be changed but not removed — an empty one shows as a blank line.")
                    .font(.system(size: Typography.Size.meta))
                    .foregroundStyle(Tokens.Ink.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Tokens.Space.s5)
        }
        .background(Tokens.Ground.milk)
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Toast(errorMessage).padding(.bottom, Tokens.Space.s8)
            }
        }
    }

    /// Stores what was typed, not what iOS would prefer.
    ///
    /// The default `.sentences` capitalisation turned "maya k." into
    /// "Maya k." on the way in — a silent edit of the user's own name, in an
    /// app whose voice is lowercase throughout. Same shape as GLO-183, where a
    /// handle field displayed a different value from the one it would claim.
    /// iOS-only: the modifier does not exist on macOS, which this package also
    /// builds for.
    @ViewBuilder private var nameField: some View {
        #if os(iOS)
            GlossedInput("your name", text: $typed)
                .textInputAutocapitalization(.never)
        #else
            GlossedInput("your name", text: $typed)
        #endif
    }

    private func performSave() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            try await save(trimmed)
            onSaved()
        } catch {
            // Stated, never swallowed. A save that reports nothing on a refused
            // write is how linked socials looked correct while being dead
            // (GLO-216).
            errorMessage = (error as? GlossedError)?.userMessage ?? "that didn't save. try again."
        }
    }
}
