import SwiftUI

/// The app's floating tab bar, built to the kit's own FloatingNav: an
/// ink-ringed capsule of ICON-ONLY tabs (the label is for screen readers —
/// the kit never draws it) with the plus riding OUTSIDE on the right
/// (Sean's Aug 29 ruling — the add action is not a tab). The active tab
/// wears cherry-soft in its own ring; inactive tabs sit at half opacity.
/// The "you" tab is the kit's Avatar, not a person glyph — the nav points
/// at YOUR profile, so it wears your initial.
public struct FloatingNav<TabID: Hashable>: View {
    /// What a tab draws — the kit's three marks. `avatar` carries the
    /// signed-in name; the shell supplies it.
    public enum Glyph {
        case discover, stylist, shelf
        case avatar(name: String)
    }

    public struct Tab: Identifiable {
        public let id: TabID
        /// Screen-reader name only — never rendered (the kit draws no text).
        public let label: String
        public let glyph: Glyph

        public init(id: TabID, label: String, glyph: Glyph) {
            self.id = id
            self.label = label
            self.glyph = glyph
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
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, Tokens.Space.s2)
        .background(Tokens.Ground.card)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
        .background(
            Capsule().fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.lg, y: Tokens.Shadow.lg)
        )
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isActive = tab.id == active
        return Button {
            active = tab.id
        } label: {
            glyphView(tab.glyph)
                .foregroundStyle(Tokens.Ink.primary)
                .frame(width: 50, height: 42)
                .background(isActive ? Tokens.Cherry.soft : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(
                    isActive ? Tokens.Ink.primary : Color.clear,
                    lineWidth: Tokens.Border.thin
                ))
                .opacity(isActive ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.pop(), value: isActive)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        // Publishes where this tab actually sits, so the onboarding tour can
        // point at one (GLO-245). The nav is the only thing that knows: its
        // own frame includes the `+`, the capsule adds padding, and a caller
        // dividing the whole bar into equal parts lands between two tabs —
        // which is exactly what the tour did before this existed.
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FloatingNavTabAnchors.self,
                    value: [tab.label: proxy.frame(in: .global).midX]
                )
            }
        }
    }

    @ViewBuilder
    private func glyphView(_ glyph: Glyph) -> some View {
        switch glyph {
        case .discover:
            SparklesIcon()
        case .stylist:
            StylistIcon()
        case .shelf:
            ShelfIcon()
        case let .avatar(name):
            Avatar(name: name, size: 26)
        }
    }

    private var plusButton: some View {
        Button(action: onPlus) {
            PlusIcon()
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Tokens.Cherry.base)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
                .background(
                    Circle().fill(Tokens.Ink.primary)
                        .offset(x: Tokens.Shadow.lg, y: Tokens.Shadow.lg)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("create")
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

/// The + drawer: add · import · collection · routine · post a look.
public struct ActionDrawer: View {
    /// The drawer's marks, hand-ported from `G.ICONS` — the four the kit's own
    /// `G.drawerOptions` names, in the same order (`search` · `file` ·
    /// `folder` · `layers`), each drawn at the kit's `size={18}`.
    ///
    /// They replace `magnifyingglass` / `doc.text` / `folder` / `square.stack`,
    /// which is GLO-64 exactly: the kit ships these and screens kept reaching
    /// past them. SF Symbols are a different drawing system with their own
    /// optical sizing, and mixing them is visible on any screen holding both.
    ///
    /// `camera` is the fifth (GLO-254). `G.drawerOptions` draws four, so the
    /// door is a stated divergence — but the *mark* is not invented: `G.ICONS`
    /// ships `camera`, fetched from the kit this session and ported on the
    /// same 24-grid as its four siblings. GLO-64 forbids reaching past the
    /// kit's icon set, not using a part of it the drawer had not needed yet.
    public enum Glyph: Sendable {
        case search, file, folder, layers, camera
    }

    public struct Option: Identifiable {
        public let id = UUID()
        public let label: String
        public let subtitle: String
        public let glyph: Glyph
        public let tint: GlossedCard<EmptyView>.Tint
        public let action: () -> Void

        public init(
            label: String,
            subtitle: String,
            glyph: Glyph,
            tint: GlossedCard<EmptyView>.Tint,
            action: @escaping () -> Void
        ) {
            self.label = label
            self.subtitle = subtitle
            self.glyph = glyph
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

    /// The card the kit puts around every option, and the built drawer never
    /// had (GLO-255). `11/12` and `14` are the kit's own inline numbers rather
    /// than tokens — `tokens/*.css` does not carry them, and this file already
    /// ports the nav's `50×42` and `spacing: 2` the same way.
    private static let rowRadius: CGFloat = 14
    private static let rowPaddingV: CGFloat = 11

    public var body: some View {
        // `s4`, not the sheet's default `s5`: the kit's drawer is `12px 16px
        // 24px`, and now that each row carries its own border the page margin
        // would read as a second inset inside the first.
        GlossedSheet(horizontalPadding: Tokens.Space.s4) {
            // `s2` = the kit's `gap:8` between rows. It was `s3`.
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                // The kit writes this in the hand — Caveat 22, cherry-deep,
                // tilted a degree — not in flat display ink. It is the loudest
                // single thing the port dropped: the kind of difference that
                // reads as "off" without being nameable.
                Text(title)
                    .handAside()
                    .rotationEffect(Tokens.Rotate.r3)
                    .padding(.horizontal, Tokens.Space.s1)
                    .padding(.bottom, Tokens.Space.s2)
                ForEach(options) { option in
                    Button(action: option.action) { row(option) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.label), \(option.subtitle)")
                }
            }
        }
    }

    private func row(_ option: Option) -> some View {
        HStack(spacing: Tokens.Space.s3) {
            DrawerGlyphView(glyph: option.glyph)
                .foregroundStyle(Tokens.Ink.primary)
                // 38, not 42 — and the kit's chips carry the sticker shadow.
                .frame(width: 38, height: 38)
                .background(option.tint.fill)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin)
                )
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .fill(Tokens.Ink.primary)
                        .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
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
        .padding(.vertical, Self.rowPaddingV)
        .padding(.horizontal, Tokens.Space.s3)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Self.rowRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.rowRadius)
                .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.rowRadius))
    }
}
