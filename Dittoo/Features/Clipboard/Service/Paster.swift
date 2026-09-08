import AppKit
import Carbon.HIToolbox

enum Paster {
    enum CopyReason: Equatable {
        case accessibility, targetUnavailable, eventUnavailable
    }

    enum Failure: Equatable {
        case unavailable, clipboardChanged, cancelled
    }

    enum Result: Equatable {
        case posted
        case copied(CopyReason)
        case failed(Failure)

        var didCopy: Bool {
            switch self {
            case .posted, .copied: true
            case .failed: false
            }
        }
    }

    /// The system boundary is injectable so permission, activation, and delayed delivery are testable.
    @MainActor
    struct Environment {
        var hasAccessibility: () -> Bool
        var isAvailable: (NSRunningApplication) -> Bool
        var activate: (NSRunningApplication) -> Bool
        var frontmostPID: () -> pid_t?
        var wait: (TimeInterval) async -> Bool
        var post: (pid_t) -> Bool

        static let live = Environment(
            hasAccessibility: { Permissions.isAccessibilityTrusted() },
            isAvailable: { !$0.isTerminated },
            activate: { $0.activate() },
            frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            wait: { delay in
                do {
                    try await Task.sleep(for: .seconds(delay))
                    return true
                } catch {
                    return false
                }
            },
            post: { postCommandV(toPid: $0) })
    }

    /// Stamped on Dittoo's synthetic keystrokes so they remain identifiable to the system.
    static let syntheticEventTag: Int64 = 0x434C4950

    /// Covers the gap between `activate()` returning and the target app accepting a keystroke.
    private static let activationDelay: TimeInterval = 0.08

    /// Shorter: no activation to wait on, only the pasteboard write reaching the target's process.
    private static let directPostDelay: TimeInterval = 0.05

    /// Write the item and paste it into `previousApp`, activating it so ⌘V lands there.
    @MainActor
    static func paste(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?,
        keepWindowOpen: Bool = false, pasteboard: NSPasteboard = .general,
        environment: Environment = .live, beforePaste: () -> Void = {}
    ) async -> Result {
        guard let changeCount = write(item, store: store, pasteboard: pasteboard) else {
            return .failed(.unavailable)
        }
        guard let app = previousApp, environment.isAvailable(app) else { return .copied(.targetUnavailable) }
        guard environment.hasAccessibility() else { return .copied(.accessibility) }

        // Keep the panel visible until copying, the target, and permission have all been checked.
        beforePaste()
        if !keepWindowOpen, !environment.activate(app) { return .copied(.targetUnavailable) }
        guard await environment.wait(keepWindowOpen ? directPostDelay : activationDelay), !Task.isCancelled else {
            return .failed(.cancelled)
        }
        guard pasteboard.changeCount == changeCount else { return .failed(.clipboardChanged) }
        guard environment.isAvailable(app),
            keepWindowOpen || environment.frontmostPID() == app.processIdentifier
        else { return .copied(.targetUnavailable) }
        guard environment.hasAccessibility() else { return .copied(.accessibility) }
        guard environment.post(app.processIdentifier) else { return .copied(.eventUnavailable) }
        return .posted
    }

    /// Put the item on the pasteboard without pasting; the marker stops re-capture.
    @MainActor @discardableResult
    static func copy(_ item: ClipboardItem, store: ClipboardStore, pasteboard: NSPasteboard = .general) -> Bool {
        write(item, store: store, pasteboard: pasteboard) != nil
    }

    /// Paste into `app` without activating it, so the palette stays open.
    @MainActor
    static func pasteInPlace(
        _ item: ClipboardItem, store: ClipboardStore, into app: NSRunningApplication?,
        pasteboard: NSPasteboard = .general, environment: Environment = .live
    ) async -> Result {
        await paste(item, store: store, previousApp: app, keepWindowOpen: true,
            pasteboard: pasteboard, environment: environment)
    }

    /// Whether anything was written; a vanished item leaves the pasteboard untouched.
    @MainActor
    private static func write(_ item: ClipboardItem, store: ClipboardStore, pasteboard: NSPasteboard) -> Int? {
        let content = NSPasteboardItem()
        switch item.kind {
        case .text:
            guard let text = item.text, content.setString(text, forType: .string) else { return nil }
        case .image:
            guard let url = store.imageURL(for: item), let data = try? Data(contentsOf: url),
                content.setData(data, forType: .png)
            else {
                return nil
            }
        }
        guard content.setData(Data(), forType: ClipboardManager.internalType) else { return nil }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([content]) else { return nil }
        let changeCount = pasteboard.changeCount
        // The poller skips marked writes, so this is the only promotion point.
        store.promote(item)
        return changeCount
    }

    /// Posting only to the captured process prevents an activation race from pasting into another app.
    @MainActor
    private static func postCommandV(toPid pid: pid_t) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)

        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return false }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)

        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }
}
