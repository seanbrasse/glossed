import SwiftUI

/// The nav grows with its labels now (GLO-201, Sean's ruling), so its icons
/// grow too. Caption type reaches roughly 3.2x at the largest accessibility
/// size, and an icon that stopped at the shared 1.6 would sit small in a bar
/// that kept going.
private let navMaxScale: CGFloat = 3.2

/// The app's floating tab bar: three tabs in V1, with the plus button riding
/// OUTSIDE the capsule on its right, vertically inline (Sean's Aug 29 ruling —
/// the add action is not a tab, and inside the capsule it read as one). A
/// fourth tab arrives only with the feed in phase 2 — V1 ships nothing
/// user-visible-to-user, so there is nothing to feed.
public struct FloatingNav<TabID: Hashable>: View {
    public struct Tab: Identifiable {
        public let id: TabID
        public let label: String
        public let systemImage: String

        public init(id: TabID, label: String, systemImage: String) {
            self.id = id
            self.label = label
            self.systemImage = systemImage
        }
    }

    let tabs: [Tab]
    @Binding var active: TabID
    let onPlus: () -> Void

    public init(tabs: [Tab], active: Binding<TabID>, onPlus: @escaping () -> Void) {
        self.tabs = tabs
        _active = active
        self.onPlus = onPlus
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s3) {
            capsule
            plusButton
        }
    }

    private var capsule: some View {
        HStack(spacing: Tokens.Space.s1) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
        }
        .padding(Tokens.Space.s2)
        .background(Tokens.Ground.card)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
        .background(
            Capsule().fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.lg, y: Tokens.Shadow.lg)
        )
    }

    /// The plus is an icon in a circle with nothing to truncate, so it grows
    /// to stay a comfortable target rather than tracking the labels — at
    /// caption's full curve it would eat a third of the screen's width.
    @ScaledMetric(relativeTo: .caption) private var plusGrown: CGFloat = 46
    private var plusSize: CGFloat {
        min(plusGrown, 46 * Typography.controlMaxScale)
    }

    /// Height grows freely — that is the ruling, and vertical space is what a
    /// floating bar has to give. Width is capped at 1.4x, which is all three
    /// tabs plus the plus button can spend on the narrowest phone we support
    /// (375pt) before the bar runs off the screen. Sizes against .caption to
    /// track Typography.mono, which is what the label is.
    @ScaledMetric(relativeTo: .caption) private var tabWidthGrown: CGFloat = 56
    @ScaledMetric(relativeTo: .caption) private var tabHeight: CGFloat = 46
    private var tabWidth: CGFloat {
        min(tabWidthGrown, 56 * 1.4)
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isActive = tab.id == active
        return Button {
            active = tab.id
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(Typography.control(17, weight: isActive ? .bold : .medium, maxScale: navMaxScale))
                Text(tab.label)
                    .font(Typography.mono(9.5))
                    // One line that shrinks, never a broken one. A tab label is
                    // a single word, so wrapping it splits it mid-word —
                    // "discov / er" — and a name in halves is worse than a name
                    // slightly smaller. It still ends up far larger than the
                    // frozen 9.5pt this replaced.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(isActive ? Tokens.Cherry.deep : Tokens.Ink.soft)
            .frame(width: tabWidth, height: tabHeight)
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.pop(), value: isActive)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var plusButton: some View {
        Button(action: onPlus) {
            Image(systemName: "plus")
                .font(Typography.control(20, maxScale: navMaxScale))
                .foregroundStyle(.white)
                .frame(width: plusSize, height: plusSize)
                .background(Tokens.Cherry.base)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin))
                // Standing alone now, it floats the way the capsule does —
                // same hard ink shadow, or the two read as different layers.
                .background(
                    Circle().fill(Tokens.Ink.primary)
                        .offset(x: Tokens.Shadow.lg, y: Tokens.Shadow.lg)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("add")
    }
}

/// In-screen filter row — flat pills, no shadow, so it never competes with the
/// floating nav for attention.
public struct TabBar<TabID: Hashable>: View {
    let options: [(id: TabID, label: String)]
    @Binding var active: TabID

    public init(options: [(id: TabID, label: String)], active: Binding<TabID>) {
        self.options = options
        _active = active
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s2) {
                ForEach(options, id: \.id) { option in
                    let isActive = option.id == active
                    Button { active = option.id } label: {
                        Text(option.label)
                            .font(Typography.mono(10.5))
                            .foregroundStyle(Tokens.Ink.primary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, Tokens.Space.s3)
                            .background(isActive ? Tokens.Cherry.soft : Tokens.Ground.card)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    isActive ? Tokens.Ink.primary : Tokens.Ground.line,
                                    lineWidth: isActive ? Tokens.Border.std : Tokens.Border.hair
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

/// The + drawer: add · import · collection · routine.
public struct ActionDrawer: View {
    public struct Option: Identifiable {
        public let id = UUID()
        public let label: String
        public let subtitle: String
        public let systemImage: String
        public let tint: GlossedCard<EmptyView>.Tint
        public let action: () -> Void

        public init(
            label: String,
            subtitle: String,
            systemImage: String,
            tint: GlossedCard<EmptyView>.Tint,
            action: @escaping () -> Void
        ) {
            self.label = label
            self.subtitle = subtitle
            self.systemImage = systemImage
            self.tint = tint
            self.action = action
        }
    }

    let title: String
    let options: [Option]

    public init(title: String = "what are we making?", options: [Option]) {
        self.title = title
        self.options = options
    }

    public var body: some View {
        GlossedSheet {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text(title)
                    .font(Typography.display(21))
                    .padding(.bottom, Tokens.Space.s1)
                ForEach(options) { option in
                    Button(action: option.action) {
                        HStack(spacing: Tokens.Space.s3) {
                            Image(systemName: option.systemImage)
                                .font(Typography.control(17, weight: .semibold))
                                .foregroundStyle(Tokens.Ink.primary)
                                .frame(width: 42, height: 42)
                                .background(option.tint.fill)
                                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin)
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.label)
                                    .font(Typography.display(15.5, weight: 700))
                                    .foregroundStyle(Tokens.Ink.primary)
                                Text(option.subtitle).meta()
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: Tokens.hitTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.label), \(option.subtitle)")
                }
            }
        }
    }
}
