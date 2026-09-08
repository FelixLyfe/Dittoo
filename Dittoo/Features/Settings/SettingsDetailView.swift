import SwiftUI

struct SettingsDetailView: View {
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        Group {
            switch navigation.tab {
            case .general: GeneralSettingsView()
            case .clipboard: ClipboardSettingsView()
            case .permissions: PermissionsSettingsView()
            case .about: AboutView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .contentBackground, blending: .behindWindow)
                .ignoresSafeArea()
        )
        .shortcutRecorderPopoverHost()
    }
}
