import Foundation

enum HotKeyBinding: Hashable, Sendable, Codable {
    case combo(KeyShortcut)

    @MainActor var keycaps: [String] {
        switch self {
        case .combo(let shortcut): shortcut.keycaps
        }
    }

    var shortcut: KeyShortcut {
        switch self {
        case .combo(let shortcut): shortcut
        }
    }
}
