import Foundation

enum HotKeyAction: Hashable, Sendable {
    case toggleClipboard

    var defaultsKey: String { "hotkey.toggleClipboard" }
}
