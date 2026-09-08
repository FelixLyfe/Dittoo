import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("History") {
                ClipboardStorageStatus(store: core.clipboardStore)
                Picker("Keep clipboard history", selection: $settings.clipboardRetention) {
                    ForEach(ClipboardRetention.allCases) { retention in
                        Text(retention.title).tag(retention)
                    }
                }
                Button("Clear Clipboard History…", role: .destructive) {
                    Task { await core.clipboardCoordinator.deleteAllClips() }
                }
            }

            Section {
                ForEach(settings.clipboardDisabledApps, id: \.self) { bundleID in
                    ExcludedApplicationRow(bundleID: bundleID) {
                        settings.clipboardDisabledApps.removeAll { $0 == bundleID }
                    }
                }
                Button("Add Application…") { chooseApplication() }
            } header: {
                Text("Excluded Applications")
            } footer: {
                Text("Dittoo ignores clipboard changes made by these applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose an application to exclude")
        panel.prompt = String(localized: "Exclude")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                let bundleID = Bundle(url: url)?.bundleIdentifier,
                !settings.clipboardDisabledApps.contains(bundleID)
            else { return }
            settings.clipboardDisabledApps.append(bundleID)
        }
    }
}

private struct ExcludedApplicationRow: View {
    let bundleID: String
    let remove: () -> Void

    private var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var body: some View {
        SettingsRow(
            title: applicationURL?.deletingPathExtension().lastPathComponent ?? bundleID,
            subtitle: bundleID,
            icon: {
                if let applicationURL {
                    Image(nsImage: IconCache.icon(forFile: applicationURL.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app.dashed")
                        .frame(width: 24, height: 24)
                }
            }
        ) {
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove application")
        }
    }
}
