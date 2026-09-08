import SwiftUI

/// Owns Dittoo's single-page first-run window.
@MainActor
final class OnboardingCoordinator {
    private let window: AppWindowController
    private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: String(localized: "Welcome to Dittoo"),
            contentSize: OnboardingView.windowSize,
            activation: core.activationPolicy)
    }

    func showOnboarding() {
        window.show {
            OnboardingView()
                .environment(self.core)
                .environment(self.core.hotKeys)
        }
    }

    func close() { window.close() }

    func focusExisting() -> Bool { window.focus() }
}
