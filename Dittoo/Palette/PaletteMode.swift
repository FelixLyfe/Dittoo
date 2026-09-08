import AppKit

enum PaletteMode {
    case clipboard

    var title: String { String(localized: "Clipboard") }
    var systemImage: String { "doc.on.clipboard" }
    var placeholder: String { String(localized: "Type to filter entries…") }
}

/// The app a paste lands in, resolved once per show.
struct PasteTarget: Equatable {
    let name: String
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { String(localized: "Paste to \(name)") }
}
