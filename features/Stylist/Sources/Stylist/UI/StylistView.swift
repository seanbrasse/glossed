import DesignSystem
import SwiftUI

/// The stylist tab (docs/tech/08-stylist.md): the thread, the chips above
/// the input, the input. Every crossing out of the chat — a look, a
/// collection, a product — is the app's, handed in as a closure.
public struct StylistView: View {
    @State private var model: StylistModel
    private let onOpenLook: ((UUID) -> Void)?
    private let onOpenCollection: ((UUID) -> Void)?
    private let onOpenProduct: ((UUID) -> Void)?
    private let imageURL: ((String) -> URL?)?
    private let shelfCount: Int?

    public init(
        model: StylistModel,
        shelfCount: Int? = nil,
        imageURL: ((String) -> URL?)? = nil,
        onOpenLook: ((UUID) -> Void)? = nil,
        onOpenCollection: ((UUID) -> Void)? = nil,
        onOpenProduct: ((UUID) -> Void)? = nil
    ) {
        _model = State(initialValue: model)
        self.shelfCount = shelfCount
        self.imageURL = imageURL
        self.onOpenLook = onOpenLook
        self.onOpenCollection = onOpenCollection
        self.onOpenProduct = onOpenProduct
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            switch model.phase {
            case .notYet:
                notice(
                    "the stylist is for adults for now.",
                    line: "your shelf, rankings and routines are all still yours."
                )
            case .unconfigured:
                notice(
                    "the stylist isn't set up on this build yet.",
                    line: "everything else works. it needs a key on the server."
                )
            case .idle, .thinking:
                thread
                composer
            }
        }
        .background(Tokens.Ground.milk)
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Toast(message).padding(.bottom, Tokens.Space.s12)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("stylist")
                .font(Typography.display(Typography.Size.h1))
                .foregroundStyle(Tokens.Ink.primary)
            Spacer()
            if let shelfCount {
                Text("knows your shelf · \(shelfCount) \(shelfCount == 1 ? "product" : "products")").meta()
            }
        }
        .padding(.horizontal, Tokens.Space.s5)
        .padding(.bottom, Tokens.Space.s3)
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    if model.isEmpty {
                        emptyState
                    }
                    ForEach(model.messages) { message in
                        StylistMessageView(
                            message: message,
                            model: model,
                            imageURL: imageURL,
                            onOpenLook: onOpenLook,
                            onOpenCollection: onOpenCollection,
                            onOpenProduct: onOpenProduct
                        )
                        .id(message.id)
                    }
                    if model.phase == .thinking {
                        Text("thinking…").meta().padding(.horizontal, Tokens.Space.s5)
                    }
                }
                .padding(.vertical, Tokens.Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.messages.count) {
                if let last = model.messages.last?.id {
                    withAnimation(Tokens.Motion.pop()) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            Text("ask about your skin, your hair, or anything on your shelf.")
                .font(Typography.display(Typography.Size.h2))
                .foregroundStyle(Tokens.Ink.primary)
            Text(
                "it reads your fit answers, what you own and what you've ranked — "
                    + "and stays on beauty. it does not diagnose."
            )
            .font(Typography.control(Typography.Size.body, weight: .regular))
            .foregroundStyle(Tokens.Ink.soft)
            Text("it only knows what you've logged")
                .handAside()
                .rotationEffect(Tokens.Rotate.r2)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Tokens.Space.s5)
        .padding(.top, Tokens.Space.s6)
    }

    private var composer: some View {
        VStack(spacing: Tokens.Space.s3) {
            if !model.chips.isEmpty {
                chipRow
            }
            HStack(spacing: Tokens.Space.s3) {
                GlossedInput("ask your stylist…", text: $model.draft, typing: .sentences)
                    .onSubmit { model.sendDraft() }
                IconButton("arrow.up", label: "send", pop: true) { model.sendDraft() }
                    .disabled(!model.canSend)
            }
            .padding(.horizontal, Tokens.Space.s5)
        }
        .padding(.bottom, Tokens.Space.s3)
    }

    /// The human-in-the-loop row: the stylist's proposals, one tap each.
    /// Nothing acts without the tap.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s2) {
                ForEach(Array(model.chips.enumerated()), id: \.offset) { index, chip in
                    Button { model.tap(chip: chip) } label: {
                        Text(chip)
                            .font(Typography.mono(Typography.Size.tag))
                            .foregroundStyle(Tokens.Ink.primary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, Tokens.Space.s3)
                            .background(Tokens.Ground.card, in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    index == 0 ? Tokens.Ink.primary : Tokens.Ground.line,
                                    lineWidth: Tokens.Border.thin
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.phase != .idle)
                }
            }
            .padding(.horizontal, Tokens.Space.s5)
        }
    }

    private func notice(_ headline: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text(headline)
                .font(Typography.display(Typography.Size.h2))
                .foregroundStyle(Tokens.Ink.primary)
            Text(line).meta()
            Spacer()
        }
        .padding(.horizontal, Tokens.Space.s5)
        .padding(.top, Tokens.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One message: the person's on the right in a card, the stylist's as text
/// under an eyebrow, with its artifacts below.
struct StylistMessageView: View {
    let message: StylistModel.Message
    let model: StylistModel
    let imageURL: ((String) -> URL?)?
    let onOpenLook: ((UUID) -> Void)?
    let onOpenCollection: ((UUID) -> Void)?
    let onOpenProduct: ((UUID) -> Void)?

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: Tokens.Space.s10)
                VStack(alignment: .trailing, spacing: Tokens.Space.s1) {
                    Text(message.text)
                        .font(Typography.control(Typography.Size.body, weight: .regular))
                        .foregroundStyle(Tokens.Ink.primary)
                        .padding(.vertical, Tokens.Space.s3)
                        .padding(.horizontal, Tokens.Space.s4)
                        .background(Tokens.Ground.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.lg))
                        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                            .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair))
                    if message.isPending, model.phase == .idle {
                        Button("didn't send — try again") { model.retry() }
                            .buttonStyle(.glossed(.secondary, size: .sm))
                    }
                }
            }
            .padding(.horizontal, Tokens.Space.s5)
        case .stylist:
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text("stylist").eyebrow()
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(Typography.control(Typography.Size.body, weight: .regular))
                        .foregroundStyle(Tokens.Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .padding(.horizontal, Tokens.Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func blockView(_ block: StylistBlock) -> some View {
        switch block {
        case let .routine(draft):
            RoutineDraftCard(
                draft: draft,
                saved: model.savedRoutines.contains(draft),
                saving: model.savingRoutine == draft,
                onSave: model.canSaveRoutines ? { model.save(routine: draft) } : nil
            )
        case let .products(list):
            ProductListCard(list: list, imageURL: imageURL, onOpen: onOpenProduct)
        case let .look(look):
            LookRefCard(look: look, onOpen: onOpenLook)
        case let .collection(collection):
            CollectionRefCard(collection: collection, onOpen: onOpenCollection)
        }
    }
}
