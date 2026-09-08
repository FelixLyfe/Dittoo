import AppKit

@main
@MainActor
struct ActivationPolicyTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        defer { app.setActivationPolicy(.accessory) }
        let policy = ActivationPolicy()
        let first = NSWindow()
        let second = NSWindow()
        var failures = 0
        policy.windowDidOpen(first)
        if app.activationPolicy() != .accessory { failures += 1 }
        policy.windowDidOpen(second)
        if app.activationPolicy() != .accessory { failures += 1 }
        policy.windowDidClose(first)
        if app.activationPolicy() != .accessory { failures += 1 }
        policy.windowDidClose(second)
        if app.activationPolicy() != .accessory { failures += 1 }
        print("Window activation: \(failures) Dock-policy failures")
        if failures > 0 { exit(1) }
    }
}
