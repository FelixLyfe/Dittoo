import AppKit
import Carbon.HIToolbox

/// Local monitors for the one active ordinary key-combination recording.
@MainActor
@Observable
final class ShortcutCaptureSession {
    struct Conflict: Equatable {
        let binding: HotKeyBinding
        let owner: String
    }

    private(set) var heldModifiers: NSEvent.ModifierFlags = []
    private(set) var conflict: Conflict?

    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var conflictReset: Task<Void, Never>?

    func start(action: HotKeyAction, hotKeys: HotKeyManager) {
        stop()
        heldModifiers = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self, weak hotKeys] event in
                MainActor.assumeIsolated {
                    guard let self, let hotKeys else { return }
                    self.handleKeyDown(event, action: action, hotKeys: hotKeys)
                }
                return nil
            })
        {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: { [weak self] event in
                MainActor.assumeIsolated {
                    self?.heldModifiers = event.modifierFlags.intersection(
                        [.command, .option, .control, .shift])
                }
                return event
            })
        {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak hotKeys] event in
                MainActor.assumeIsolated { hotKeys?.recordingAction = nil }
                return event
            })
        {
            monitors.append(monitor)
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak hotKeys] _ in
            MainActor.assumeIsolated { hotKeys?.recordingAction = nil }
        }
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        conflictReset?.cancel()
        conflictReset = nil
        conflict = nil
        heldModifiers = []
    }

    private func handleKeyDown(
        _ event: NSEvent, action: HotKeyAction, hotKeys: HotKeyManager
    ) {
        let keyCode = Int(event.keyCode)
        let flags = event.modifierFlags
        let bareKey = flags.isDisjoint(with: [.command, .option, .control, .shift])

        if bareKey, keyCode == kVK_Escape {
            hotKeys.recordingAction = nil
            return
        }
        if bareKey, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            hotKeys.setBinding(nil, for: action)
            hotKeys.recordingAction = nil
            return
        }
        guard let shortcut = KeyShortcut(keyCode: keyCode, modifierFlags: flags) else { return }
        let candidate = HotKeyBinding.combo(shortcut)
        if let owner = hotKeys.conflictOwner(of: candidate, excluding: action) {
            flashConflict(Conflict(binding: candidate, owner: owner))
            return
        }
        hotKeys.setBinding(candidate, for: action)
        hotKeys.recordingAction = nil
    }

    private func flashConflict(_ rejected: Conflict) {
        conflict = rejected
        conflictReset?.cancel()
        conflictReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.conflict = nil
        }
    }
}
