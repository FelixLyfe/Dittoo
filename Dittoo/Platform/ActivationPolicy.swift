import AppKit

/// Ordinary windows can receive focus while Dittoo remains a menu-bar-only accessory.
@MainActor
final class ActivationPolicy {
    func windowDidOpen(_: NSWindow) {
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidClose(_: NSWindow) {
        NSApp.setActivationPolicy(.accessory)
    }
}
