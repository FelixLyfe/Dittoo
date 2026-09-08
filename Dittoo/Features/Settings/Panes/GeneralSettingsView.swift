import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Global Shortcut") {
                SettingsRow(
                    title: String(localized: "Clipboard History"),
                    subtitle: String(localized: "Open Dittoo from any app.")
                ) {
                    ShortcutRecorder(action: .toggleClipboard)
                }
            }
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
            }
            Section {
                Picker("Language", selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            } header: {
                Text("General")
            } footer: {
                Text("Language changes take effect after restarting Dittoo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
