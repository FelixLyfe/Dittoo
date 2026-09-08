import AppKit
import Foundation

@main
@MainActor
struct MenuBarIconTests {
    static func main() {
        let path = "Dittoo/Assets.xcassets/MenuBarIcon.imageset/Dittoo-menu-bar-icon.svg"

        guard let image = NSImage(contentsOfFile: path) else {
            print("FAIL: menu-bar icon did not load")
            exit(1)
        }

        let size = image.size
        let isMenuBarSized = size.width == 18 && size.height == 18
        if !isMenuBarSized {
            print("FAIL: menu-bar icon is \(Int(size.width))x\(Int(size.height)) pt, expected 18x18 pt")
        }

        exit(isMenuBarSized ? 0 : 1)
    }
}
