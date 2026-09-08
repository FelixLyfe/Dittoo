import SwiftUI

// The few pieces more than one Settings pane needs; everything else is a stock `Form` section.

/// Not `LabeledContent`: its selectable text field eats the taps a `ShortcutRecorder` needs.
struct SettingsRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            icon
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(subtitle)
                }
            }
            Spacer(minLength: Theme.Spacing.lg)
            trailing
        }
    }
}

extension SettingsRow where Icon == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, icon: { EmptyView() }, trailing: trailing)
    }
}
