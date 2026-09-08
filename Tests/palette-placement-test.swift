import CoreGraphics
import Foundation

@main
@MainActor
struct PalettePlacementTests {
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

    static func main() {
        let screen = CGRect(x: 1800, y: 20, width: 1920, height: 1055)
        let anchor = PalettePlacement.defaultAnchor(
            in: screen, width: Theme.Size.panelWidth,
            topMarginFraction: Theme.Size.paletteTopMarginFraction)
        expect(anchor.x == screen.midX - Theme.Size.panelWidth / 2, "centres on target screen")
        expect(anchor.y < screen.maxY, "top edge remains inside the visible frame")
        expect(
            anchor.y - Theme.Size.panelHeight > screen.minY,
            "the full clipboard palette fits below its anchor")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
