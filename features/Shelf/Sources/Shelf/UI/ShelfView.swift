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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                heading
                domainFilter
                if model.showsFragranceNote {
                    Text("fragrance ranks by face-off only — no shade or skin axis, and we don't invent one")
                        .meta()
                }
                sortPills
                ShelfBayView(bays: model.bays, onTap: onTapItem)
            }
            // 110pt of bottom room: the floating nav sits over this screen.
            .padding(.init(top: 14, leading: 16, bottom: 110, trailing: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.Ground.milk)
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
