import SwiftUI

@main
struct DittooApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private let appName = Bundle.main.appDisplayName

    init() {
        AppLanguage.prepareForLaunch()
    }

    var body: some Scene {
        MenuBarExtra(appName, image: "MenuBarIcon") {
            Button("Clipboard History") {
                AppCore.shared.paletteCoordinator.showClipboard()
            }
            Divider()
            Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
            Button(String(localized: "About \(appName)")) {
                AppCore.shared.settingsCoordinator.showAbout()
            }
            Divider()
            Button(String(localized: "Quit \(appName)")) { NSApp.terminate(nil) }
        }
        .commands { menuBarCommands }
    }

    @CommandsBuilder
    private var menuBarCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About \(appName)")) {
                AppCore.shared.settingsCoordinator.showAbout()
            }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button(String(localized: "Quit \(appName)")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
