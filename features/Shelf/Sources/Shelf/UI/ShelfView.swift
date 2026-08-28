import DataKit
import DesignSystem
import SwiftUI

/// TAB 2 · SHELF — the screen around the bays.
///
/// Built to `G.Shelf`: the heading and a count of what is on screen, the
/// four-domain filter on its own scrolling row bled to the screen edges, the
/// fragrance note when it applies, and the sort pills.
public struct ShelfView: View {
    @State private var model: ShelfModel
    private let onTapItem: (ShelfItem) -> Void

    public init(model: ShelfModel, onTapItem: @escaping (ShelfItem) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onTapItem = onTapItem
    }

    public var body: some View {
        page
            .overlay {
                if let item = model.openItem {
                    ShelfItemSheet(
                        item: item,
                        rankedInCategory: model.rankedCount(inCategoryOf: item),
                        // Reads the model's copy, writes through the model —
                        // which is where a change is persisted and where a
                        // failed save falls back.
                        fit: Binding(
                            get: { model.openFit },
                            set: { model.fitChanged(to: $0) }
                        ),
                        onClose: model.closeSheet,
                        onRemove: model.supportsRemoval ? { model.removeOpenItem() } : nil,
                        isRemoving: model.isRemoving,
                        removeFailure: model.removeFailure?.userMessage
                    )
                }
            }
            .animation(Tokens.Motion.pop(Tokens.Motion.med), value: model.openItem)
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                heading
                domainFilter
                if model.showsFragranceNote {
                    Text("fragrance ranks by face-off only — no shade or skin axis, and we don't invent one")
                        .meta()
                }
                controls
                switch model.viewMode {
                case .shelf:
                    ShelfBayView(sections: model.shownSections, onTap: tapped)
                case .list:
                    ShelfListView(
                        sections: model.shownSections,
                        openSection: model.openSection,
                        onToggleSection: model.toggleSection,
                        onTapItem: tapped
                    )
                }
            }
            // 110pt of bottom room: the floating nav sits over this screen.
            .padding(.init(top: 14, leading: 16, bottom: 110, trailing: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.Ground.milk)
    }

    /// The sheet is the shelf's own answer to a tap; `onTapItem` is for whatever
    /// contains the shelf and wants to know as well. Both fire, and neither
    /// swallows the other — a host that navigated away would otherwise leave a
    /// sheet open behind it.
    private func tapped(_ item: ShelfItem) {
        model.open(item)
        onTapItem(item)
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("your shelf")
                .font(Typography.display(30))
                .tracking(-0.6)
                .foregroundStyle(Tokens.Ink.primary)
            Spacer(minLength: 0)
            // Counts what is on screen. A total that ignored the filter would
            // contradict the shelf directly under it.
            Badge("\(model.shownItemCount) items", tone: .cherry)
        }
    }

    /// Its own row, 44 tall, scrolling horizontally and bled to the screen
    /// edges — four domains plus "all" do not fit on a narrow phone, and a
    /// control that stops at the page margin looks like it has been cut off
    /// rather than like it continues.
    private var domainFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Segmented(
                options: ShelfModel.domains.map(\.rawValue),
                selection: Binding(
                    get: { Set(model.selectedDomains.map(\.rawValue)) },
                    set: { model.selectedDomains = Set($0.compactMap(Domain.init(rawValue:))) }
                ),
                allowsAll: true
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, -16)
    }

    /// Sort on the left, view toggle pinned right — the kit puts them on one
    /// row because they are the two things you change about the same list.
    private var controls: some View {
        HStack(alignment: .center, spacing: 8) {
            sortPills
            viewToggle
        }
    }

    /// Two 38×30 buttons inside one 2px ink pill, so it reads as a single
    /// control with two states rather than as two buttons that happen to touch.
    private var viewToggle: some View {
        HStack(spacing: 0) {
            ForEach(ShelfViewMode.allCases, id: \.self) { mode in
                Button { model.viewMode = mode } label: {
                    Image(systemName: mode == .shelf ? "square.split.1x2" : "list.bullet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Tokens.Ink.primary)
                        .frame(width: 38, height: 30)
                        .background(model.viewMode == mode ? Tokens.Cherry.soft : Tokens.Ground.card)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.rawValue) view")
                .accessibilityAddTraits(model.viewMode == mode ? [.isSelected] : [])
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
        .background(
            Capsule().fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
        )
        .fixedSize()
    }

    private var sortPills: some View {
        HStack(spacing: 6) {
            ForEach(ShelfSort.allCases, id: \.self) { option in
                Button { model.sort = option } label: {
                    Text(option.rawValue)
                        .font(Typography.mono(10.5))
                        .kerning(10.5 * 0.06)
                        .foregroundStyle(Tokens.Ink.primary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 11)
                        .background(model.sort == option ? Tokens.Cherry.soft : Tokens.Ground.card)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                model.sort == option ? Tokens.Ink.primary : Tokens.Ground.line,
                                lineWidth: model.sort == option ? Tokens.Border.std : Tokens.Border.hair
                            )
                        )
                        .background(
                            // The selected pill is the only one that lifts. Two
                            // raised pills in a row of three read as neither.
                            Capsule()
                                .fill(model.sort == option ? Tokens.Ink.primary : .clear)
                                .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("sort by \(option.rawValue)")
                .accessibilityAddTraits(model.sort == option ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }
}
