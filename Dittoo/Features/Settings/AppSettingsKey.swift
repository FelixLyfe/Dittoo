import Foundation

enum AppSettingsKey: String, CaseIterable {
    case clipboardRetention = "clipboardRetentionDays"
    case clipboardDisabledApps = "clipboardDisabledApps"
    case appearance = "appearance"
    case appLanguage = "appLanguage"
}
