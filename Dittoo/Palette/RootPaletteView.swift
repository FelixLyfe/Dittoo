import SwiftUI

struct RootPaletteView: View {
    @Environment(AppCore.self) private var core
    @Environment(PaletteState.self) private var palette
    @Environment(ClipboardStore.self) private var store
    @FocusState private var searchFocused: Bool
    @State private var openMenu: OpenMenu?
    @State private var menuSelection = 0
    @State private var scroll = ScrollIntent(kind: .top)

    private var screen: ClipboardScreen {
        ClipboardScreen(
            store: store, core: core, vm: palette, openActions: openActions,
            scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
    }

    private var selection: Int {
        let count = screen.rows.count
        return count == 0 ? 0 : min(max(palette.selection, 0), count - 1)
    }

    private var actionsContent: PopoverMenuContent? {
        screen.actions(at: selection)
    }

    private var filterContent: PopoverMenuContent {
        PopoverMenuContent(
            items: ClipboardFilter.allCases.map { filter in
                PopoverMenuItem(title: filter.title, systemImage: filter.systemImage) {
                    palette.clipboardFilter = filter
                }
            })
    }

    private var appMenuContent: PopoverMenuContent {
        let name = Bundle.main.appDisplayName
        return PopoverMenuContent(items: [
            PopoverMenuItem(
                title: String(localized: "About \(name)"), systemImage: "info.circle"
            ) {
                core.settingsCoordinator.showAbout()
            },
            PopoverMenuItem(
                title: String(localized: "Settings"), systemImage: "gearshape", shortcut: "⌘,"
            ) {
                core.settingsCoordinator.showSettings()
            }
        ])
    }

    private var menuContent: PopoverMenuContent? {
        switch openMenu {
        case .actions: actionsContent
        case .app: appMenuContent
        case .filter: filterContent
        case nil: nil
        }
    }

    var body: some View {
        let currentScreen = screen
        let currentSelection = selection

        return currentScreen.body(selection: currentSelection, scroll: scroll)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar(showActionGroup: !currentScreen.rows.isEmpty)
            }
            .overlay {
                if openMenu != nil {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: closeMenus)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if openMenu == .app {
                    PopoverMenu(
                        header: appMenuContent.header, items: appMenuContent.items,
                        selection: $menuSelection, onActivate: activateMenuItem
                    )
                    .padding(Self.menuInset)
                    .transition(Self.menuTransition(.bottomLeading))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if openMenu == .actions, let content = actionsContent {
                    PopoverMenu(
                        header: content.header, items: content.items, selection: $menuSelection,
                        onActivate: activateMenuItem
                    )
                    .padding(Self.menuInset)
                    .transition(Self.menuTransition(.bottomTrailing))
                }
            }
            .overlay(alignment: .topTrailing) {
                if openMenu == .filter {
                    PopoverMenu(
                        items: filterContent.items, selection: $menuSelection,
                        width: Theme.Size.clipboardFilterMenuWidth,
                        onActivate: activateMenuItem
                    )
                    .padding(.top, Theme.Size.headerPadding + Theme.Size.headerHeight)
                    .padding(.trailing, Theme.Spacing.md * 2)
                    .transition(Self.menuTransition(.topTrailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.Colors.panelScrim)
            .background(VisualEffectView())
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .onChange(of: palette.focusToken) {
                searchFocused = true
                openMenu = nil
            }
            .onChange(of: palette.query) {
                palette.selection = 0
                palette.clipboardResultLimit = ClipboardStore.pageSize
                scroll = ScrollIntent(kind: .top)
            }
            .onChange(of: palette.clipboardFilter) {
                palette.selection = 0
                palette.clipboardResultLimit = ClipboardStore.pageSize
                scroll = ScrollIntent(kind: .top)
            }
            .onChange(of: palette.resetToken) {
                scroll = ScrollIntent(kind: .top)
            }
            .onChange(of: palette.pinChordToken) {
                _ = screen.pin(at: selection)
            }
            .onChange(of: openMenu) {
                palette.menuOpen = openMenu != nil
            }
            .onAppear { searchFocused = true }
            .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { _ in
                if openMenu != nil {
                    moveMenu(1)
                } else {
                    moveSelection(1)
                }
                return .handled
            }
            .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { _ in
                if openMenu != nil {
                    moveMenu(-1)
                } else {
                    moveSelection(-1)
                }
                return .handled
            }
            .onKeyPress(keys: [.return], phases: .down) { press in
                let command = press.modifiers.contains(.command)
                let option = press.modifiers.contains(.option)
                if openMenu != nil, !command, !option {
                    activateMenuItem(menuSelection)
                    return .handled
                }
                guard command || option else { return .ignored }
                if command {
                    return screen.secondary(at: selection) ? .handled : .ignored
                }
                return screen.pasteKeepingWindowOpen(at: selection) ? .handled : .ignored
            }
            .onKeyPress(.escape) {
                if openMenu != nil {
                    closeMenus()
                } else {
                    core.paletteCoordinator.hidePalette()
                }
                return .handled
            }
            .onKeyPress(.tab) { .handled }
            .onKeyPress(keys: ["k"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                if !screen.rows.isEmpty { toggleActions() }
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                screen.delete(at: selection)
                return .handled
            }
            .onKeyPress(keys: ["x", "X"], phases: .down) { press in
                guard press.modifiers.contains(.control) else { return .ignored }
                if press.modifiers.contains(.shift) {
                    screen.deleteAll()
                } else {
                    screen.delete(at: selection)
                }
                closeMenus()
                return .handled
            }
            .onKeyPress(keys: ["p"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                toggleFilter()
                return .handled
            }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: PaletteMode.clipboard.systemImage)
                .font(Theme.Typography.headerIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.headerIconSlot)
            searchField
            ClipboardFilterButton(
                filter: palette.clipboardFilter, isOpen: openMenu == .filter,
                action: toggleFilter)
        }
        .padding(.horizontal, Theme.Spacing.md * 2)
        .frame(height: Theme.Size.headerHeight)
        .padding(.top, Theme.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    private var searchField: some View {
        @Bindable var palette = palette
        return TextField("", text: $palette.query)
            .textFieldStyle(.plain)
            .font(Theme.Typography.searchField)
            .tint(Theme.Colors.textPrimary)
            .focused($searchFocused)
            .onSubmit { screen.activate(at: selection) }
            .frame(maxHeight: .infinity)
            .background(alignment: .leading) {
                if palette.query.isEmpty, !palette.isComposing {
                    Text(PaletteMode.clipboard.placeholder)
                        .font(Theme.Typography.searchField)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(Text(PaletteMode.clipboard.placeholder))
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                palette.searchFieldFrame = $0
            }
    }

    private func bottomBar(showActionGroup: Bool) -> some View {
        HStack(spacing: 0) {
            MenuCircleButton {
                openMenu == .app ? closeMenus() : open(.app, highlighting: 0)
            }
            Spacer()
            if showActionGroup {
                HStack(spacing: 2) {
                    BarButton(action: { screen.activate(at: selection) }) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(screen.primaryActionTitle)
                                .font(Theme.Typography.bar)
                            KeyCapChip(text: "↵", style: .outline)
                        }
                    }
                    BarButton(action: toggleActions) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("Actions")
                                .font(Theme.Typography.bar)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            HStack(spacing: Theme.Spacing.xxs) {
                                KeyCapChip(text: "⌘", style: .outline)
                                KeyCapChip(text: "K", style: .outline)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.xs)
                .frosted(in: Capsule())
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    private func moveSelection(_ delta: Int) {
        if delta > 0, selection == screen.rows.count - 1, screen.hasMore {
            screen.loadMore()
        }
        let count = screen.rows.count
        guard count > 0 else { return }
        palette.selection = min(max(selection + delta, 0), count - 1)
        scroll = ScrollIntent(kind: .follow)
    }

    private func moveMenu(_ delta: Int) {
        guard let count = menuContent?.items.count, count > 0 else { return }
        menuSelection = min(max(menuSelection + delta, 0), count - 1)
    }

    private func openActions() {
        guard actionsContent != nil else { return }
        open(.actions, highlighting: 0)
    }

    private func toggleActions() {
        openMenu == .actions ? closeMenus() : openActions()
    }

    private func toggleFilter() {
        if openMenu == .filter {
            closeMenus()
        } else {
            let active = ClipboardFilter.allCases.firstIndex(of: palette.clipboardFilter) ?? 0
            open(.filter, highlighting: active)
        }
    }

    private func open(_ menu: OpenMenu, highlighting row: Int) {
        menuSelection = row
        withAnimation(Self.menuAnimation) { openMenu = menu }
    }

    private func closeMenus() {
        withAnimation(Self.menuAnimation) { openMenu = nil }
    }

    private func activateMenuItem(_ index: Int) {
        guard let items = menuContent?.items, items.indices.contains(index) else { return }
        items[index].action()
        closeMenus()
    }

    private static let menuInset: CGFloat = 8
    private static let menuAnimation: Animation = .easeOut(duration: 0.14)

    private static func menuTransition(_ anchor: UnitPoint) -> AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
    }
}

private enum OpenMenu {
    case actions
    case app
    case filter
}

private struct MenuCircleButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule().frame(width: 14, height: 1.5)
                Capsule().frame(width: 8, height: 1.5)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: Theme.Size.menuButton, height: Theme.Size.menuButton)
            .background(Circle().fill(hovered ? Theme.Colors.rowHover : Color.clear))
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Circle())
    }
}

private struct ArmedHover: ViewModifier {
    @Environment(PaletteState.self) private var palette
    @Binding var hovered: Bool

    func body(content: Content) -> some View {
        content
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active: hovered = palette.hoverHighlightArmed
                case .ended: hovered = false
                }
            }
            .onChange(of: palette.hoverDisarmToken) { hovered = false }
    }
}

extension View {
    func armedHover(_ hovered: Binding<Bool>) -> some View {
        modifier(ArmedHover(hovered: hovered))
    }
}

struct EmptyResults: View {
    let text: String

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.on.clipboard")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
