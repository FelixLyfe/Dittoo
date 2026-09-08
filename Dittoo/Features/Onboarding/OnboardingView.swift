import AppKit
import SwiftUI

/// One deliberate first-run page; capture starts only after the user presses Done.
struct OnboardingView: View {
    static let windowSize = CGSize(width: 540, height: 470)

    @Environment(AppCore.self) private var core

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            hero
            OnboardingCard {
                OnboardingRow(
                    title: String(localized: "Clipboard history"),
                    subtitle: String(
                        localized: "Dittoo records copied text and images after setup is complete."),
                    systemImage: "doc.on.clipboard", tint: .orange
                ) {
                    EmptyView()
                }
                OnboardingDivider()
                OnboardingRow(
                    title: String(localized: "Global shortcut"),
                    subtitle: String(localized: "Open clipboard history from any app."),
                    systemImage: "keyboard", tint: .blue
                ) {
                    ShortcutRecorder(action: .toggleClipboard)
                }
                OnboardingDivider()
                OnboardingRow(
                    title: String(localized: "Accessibility"),
                    subtitle: String(
                        localized: "Needed only when you paste an item into another app."),
                    systemImage: "accessibility", tint: .green
                ) {
                    Text("Requested on first paste")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Theme.Colors.sheen, Color.clear],
                startPoint: .top, endPoint: .center)
        )
        .ignoresSafeArea()
        .shortcutRecorderPopoverHost()
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Welcome to Dittoo")
                .font(.title2.weight(.bold))
            Text("A focused, local clipboard history for text and images.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("Nothing is captured until you finish setup.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Done") { core.completeOnboarding() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }
}
