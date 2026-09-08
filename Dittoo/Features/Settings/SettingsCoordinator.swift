import SwiftUI

@MainActor
final class SettingsCoordinator {
    private let window: AppWindowController
    private unowned let core: AppCore
    private weak var navigation: SettingsNavigationState?

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: String(localized: "Settings"), contentSize: Theme.Size.settingsWindow,
            resizable: true, autosaveName: "SettingsWindow", activation: core.activationPolicy)
    }

    func showSettings(tab: SettingsTab = .general) {
        if window.focus() {
            navigation?.select(tab)
            return
        }
        let navigation = SettingsNavigationState(tab: tab)
        self.navigation = navigation
        window.show(chrome: SettingsToolbarController(navigation: navigation)) {
            SettingsSplitViewController(
                sidebar: inject(SettingsSidebarView(), navigation),
                detail: inject(SettingsDetailView(), navigation))
        }
    }

    private func inject(_ view: some View, _ navigation: SettingsNavigationState) -> some View {
        view
            .environment(navigation)
            .environment(core)
            .environment(core.settings)
            .environment(core.hotKeys)
            .scrollContentBackground(.hidden)
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func closeSettings() {
        window.close()
    }

    func focusExisting() -> Bool {
        window.focus()
    }
}
