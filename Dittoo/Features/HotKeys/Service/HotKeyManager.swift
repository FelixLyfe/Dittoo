import Foundation

/// Owns the single global clipboard shortcut: persistence, registration, and recording.
@MainActor
@Observable
final class HotKeyManager {
    var onToggleClipboard: (() -> Void)?

    var recordingAction: HotKeyAction? {
        didSet {
            guard recordingAction != oldValue else { return }
            center.isPaused = recordingAction != nil
            if let recordingAction {
                capture.start(action: recordingAction, hotKeys: self)
            } else {
                capture.stop()
            }
        }
    }

    let capture = ShortcutCaptureSession()

    private let center = HotKeyCenter()
    private var binding: HotKeyBinding?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func start() {
        binding = storedBinding()
        register()
    }

    func binding(for action: HotKeyAction) -> HotKeyBinding? {
        action == .toggleClipboard ? binding : nil
    }

    func setBinding(_ newBinding: HotKeyBinding?, for action: HotKeyAction) {
        guard action == .toggleClipboard else { return }
        binding = newBinding
        if let newBinding, let data = try? encoder.encode(newBinding),
            let json = String(data: data, encoding: .utf8)
        {
            UserDefaults.standard.set(json, forKey: action.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
        }
        register()
    }

    func conflictOwner(of candidate: HotKeyBinding, excluding action: HotKeyAction) -> String? {
        guard action != .toggleClipboard, binding == candidate else { return nil }
        return String(localized: "Clipboard History")
    }

    private func storedBinding() -> HotKeyBinding? {
        guard
            let json = UserDefaults.standard.string(forKey: HotKeyAction.toggleClipboard.defaultsKey),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? decoder.decode(HotKeyBinding.self, from: data)
    }

    private func register() {
        let action = HotKeyAction.toggleClipboard
        center.unregister(id: action.defaultsKey)
        guard let shortcut = binding?.shortcut else { return }
        center.register(id: action.defaultsKey, shortcut: shortcut) { [weak self] in
            self?.onToggleClipboard?()
        }
    }
}
