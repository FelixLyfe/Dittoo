enum SettingsTab: CaseIterable, Identifiable {
    case general
    case clipboard
    case permissions
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .clipboard: String(localized: "Clipboard")
        case .permissions: String(localized: "Permissions")
        case .about: String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "switch.2"
        case .clipboard: "doc.on.clipboard"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

enum SettingsSection: CaseIterable, Identifiable {
    case settings
    case information

    var id: Self { self }

    var title: String {
        switch self {
        case .settings: String(localized: "Settings")
        case .information: String(localized: "Information")
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .settings: [.general, .clipboard, .permissions]
        case .information: [.about]
        }
    }
}
