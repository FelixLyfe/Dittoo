import AppKit
import SwiftUI

struct AboutView: View {
    private var version: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return String(localized: "Version \(version) (\(build))")
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Dittoo")
                .font(.title.bold())
            Text("A focused, local clipboard history for macOS.")
                .foregroundStyle(.secondary)
            Text(version)
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack(spacing: Theme.Spacing.xl) {
                Link("Source Code", destination: URL(string: "https://github.com/FelixLyfe/Dittoo")!)
                Link(
                    "AGPL-3.0 License",
                    destination: URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!)
            }
            .font(.callout)
            Text("Based on work by Abue Ammar.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
