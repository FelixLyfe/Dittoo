import SwiftUI

/// Persistence errors stay visible until history can be read or a change succeeds.
struct ClipboardStorageStatus: View {
    let store: ClipboardStore

    var body: some View {
        if let failure = store.failure {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Reload History") { store.load() }
            }
            .font(.caption)
            .padding(Theme.Spacing.md)
        }
    }
}
