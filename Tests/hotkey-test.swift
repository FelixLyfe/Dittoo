import AppKit
import Carbon.HIToolbox
import Foundation

@main
@MainActor
struct HotKeyTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() throws {
        expect(HotKeyAction.toggleClipboard.defaultsKey == "hotkey.toggleClipboard", "one action")
        expect(
            KeyShortcut(keyCode: kVK_ANSI_C, modifierFlags: []) == nil,
            "ordinary letters require a commanding modifier")
        expect(
            KeyShortcut(keyCode: kVK_ANSI_C, modifierFlags: [.shift]) == nil,
            "shift alone is not a global shortcut")

        let shortcut = KeyShortcut(keyCode: kVK_ANSI_C, modifierFlags: [.control, .option])!
        expect(shortcut.modifierFlags == [.control, .option], "modifiers round-trip")
        expect(shortcut.keycaps.prefix(2) == ["⌃", "⌥"], "modifiers render canonically")

        let binding = HotKeyBinding.combo(shortcut)
        let encoded = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(HotKeyBinding.self, from: encoded)
        expect(decoded == binding, "binding persists")

        let functionKey = KeyShortcut(keyCode: kVK_F6, modifierFlags: [])
        expect(functionKey?.keycaps == ["F6"], "function keys may stand alone")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
