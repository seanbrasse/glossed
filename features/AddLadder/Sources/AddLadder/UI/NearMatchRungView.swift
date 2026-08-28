import DesignSystem
import SwiftUI

/// Rung 3: near matches, framed as a question about the photo.
public struct NearMatchRungView: View {
    @State private var model: NearMatchRungModel
    @State private var searchTask: Task<Void, Never>?

    public init(model: NearMatchRungModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s5) {
            RungRail(trail: model.ladder.trail, current: model.ladder.rung)
            Text(prompt)
                .font(Typography.display(20))
                .foregroundStyle(Tokens.Ink.primary)
            GlossedInput("what's it called?", text: $model.query, hint: hint)
                .plainTyping()
            options
        }
        .padding(Tokens.Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.Ground.milk)
        .task { await model.search() }
        .onChange(of: model.query) { _, _ in scheduleSearch() }
    }

    /// The instruction that gives this rung its reason to exist. Two shades of
    /// one product read almost identically as text, so the name is the thing
    /// least worth trusting here.
    private var prompt: String {
        model.needsAName
            ? "the scan came up empty — what's it called?"
            : "check the photo, not the name"
    }

    private var hint: String? {
        // Failure first, and it survives a retry until an answer replaces it —
        // an unanswered list must never read as an empty one here.
        if let failure = model.failure {
            return failure.userMessage
        }
        if model.isSearching {
            return "looking…"
        }
        return nil
    }

    private var options: some View {
        ScrollView {
            LazyVStack(spacing: Tokens.Space.s3) {
                ForEach(model.options) { option in
                    LadderOptionRow(option) { model.choose(option) }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.search()
        }
    }
}
