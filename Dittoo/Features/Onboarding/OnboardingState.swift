import Foundation

/// A file marker keeps first-run state out of preferences and survives defaults resets.
enum OnboardingState {
    private static let markerURL = AppPaths.applicationSupport()
        .appendingPathComponent("onboarding-completed")

    static var hasCompleted: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Written only after Done, so Dittoo never captures during onboarding.
    static func markCompleted() {
        try? Data().write(to: markerURL, options: .atomic)
    }
}
