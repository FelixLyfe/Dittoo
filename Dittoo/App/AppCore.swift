import AppKit

/// Single owner of Dittoo's clipboard, hotkey, settings, and window lifecycles.
@MainActor
@Observable
final class AppCore {
    static let shared = AppCore()

    let settings: AppSettings
    let clipboardStore: ClipboardStore
    let clipboardManager: ClipboardManager
    let hotKeys = HotKeyManager()
    let palette = PaletteState()
    let activationPolicy = ActivationPolicy()

    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private let iconStyle = IconStyleMonitor()

    @ObservationIgnored private(set) lazy var paletteCoordinator = PaletteCoordinator(
        palette: palette, windowController: windowController)
    @ObservationIgnored private(set) lazy var settingsCoordinator = SettingsCoordinator(core: self)
    @ObservationIgnored private(set) lazy var onboardingCoordinator = OnboardingCoordinator(core: self)
    @ObservationIgnored private(set) lazy var clipboardCoordinator = ClipboardCoordinator(
        clipboardStore: clipboardStore, palette: palette, windowController: windowController,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private lazy var windowController = PaletteWindowController(core: self)

    private let dialogs = DialogController()

    private init() {
        let settings = AppSettings()
        let clipboardStore = ClipboardStore()
        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        self.settings = settings
        self.clipboardStore = clipboardStore
        clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
    }

    func start() {
        Signposts.interval("AppCore.start") {
            UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
            NSApp.setActivationPolicy(.accessory)
            applyAppearance()
            observeEffectiveAppearance()

            clipboardStore.maxAge = settings.clipboardRetention.maxAge
            clipboardStore.load()

            hotKeys.onToggleClipboard = { [weak self] in self?.paletteCoordinator.toggleClipboard() }
            hotKeys.start()
            observeSettings()

            if OnboardingState.hasCompleted {
                clipboardManager.start()
            } else {
                onboardingCoordinator.showOnboarding()
            }
        }
    }

    func completeOnboarding() {
        OnboardingState.markCompleted()
        clipboardManager.start()
        onboardingCoordinator.close()
        paletteCoordinator.showClipboard()
    }

    func handleReopen() {
        if settingsCoordinator.focusExisting() { return }
        if onboardingCoordinator.focusExisting() { return }
        paletteCoordinator.showClipboard()
    }

    private func observeSettings() {
        track({ _ = $0.appearance }, reproject: { $0.applyAppearance() })
        track({ _ = $0.clipboardRetention }) { core in
            core.clipboardCoordinator.applyRetention(core.settings.clipboardRetention)
        }
    }

    private func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    private func observeEffectiveAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial]) { app, _ in
            MainActor.assumeIsolated { IconCache.setDarkSurface(app.effectiveAppearance.isDark) }
        }
    }

    private func track(
        _ reads: @escaping @Sendable @MainActor (AppSettings) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        withObservationTracking {
            reads(settings)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.track(reads, reproject: reproject)
                reproject(self)
            }
        }
    }

    func confirm(
        title: String, message: String?, symbol: String?, confirmTitle: String,
        tone: DialogTone = .danger, confirmRole: DialogAction.Role = .destructive,
        dismissTitle: String = String(localized: "Cancel")
    ) async -> Bool {
        await dialogs.confirm(
            title: title, message: message, symbol: symbol, tone: tone, confirmTitle: confirmTitle,
            confirmRole: confirmRole, dismissTitle: dismissTitle)
    }

    func reportFailure(
        title: String, message: String, symbol: String, recovery: String?
    ) async -> Bool {
        await dialogs.reportFailure(
            title: title, message: message, symbol: symbol, recovery: recovery)
    }
}
