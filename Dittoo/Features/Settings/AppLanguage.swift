import Foundation

/// The language Dittoo uses for its own interface; changing it takes effect on next launch.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    private static let appleLanguagesKey = "AppleLanguages"

    var id: String { rawValue }

    /// Language names stay in their own language so the picker remains usable in either locale.
    var title: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    /// A fresh install follows the localization macOS selected for this bundle.
    static var systemPreferred: AppLanguage {
        Bundle.main.preferredLocalizations.first.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    static func saved(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: AppSettingsKey.appLanguage.rawValue)
            .flatMap(AppLanguage.init(rawValue:)) ?? systemPreferred
    }

    /// Set the per-app Apple language before SwiftUI creates any localized scene content.
    static func prepareForLaunch(in defaults: UserDefaults = .standard) {
        let language = saved(in: defaults)
        guard defaults.stringArray(forKey: appleLanguagesKey)?.first != language.rawValue else {
            return
        }
        defaults.set([language.rawValue], forKey: appleLanguagesKey)
    }

    func prepareForNextLaunch(in defaults: UserDefaults = .standard) {
        defaults.set([rawValue], forKey: Self.appleLanguagesKey)
    }
}
