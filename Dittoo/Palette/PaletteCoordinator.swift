import AppKit

/// Owns summoning and dismissing the clipboard panel.
@MainActor
final class PaletteCoordinator {
    private let palette: PaletteState
    private let windowController: PaletteWindowController

    init(palette: PaletteState, windowController: PaletteWindowController) {
        self.palette = palette
        self.windowController = windowController
    }

    var isVisible: Bool { windowController.isVisible }

    var targetApp: NSRunningApplication? {
        windowController.isVisible
            ? windowController.previousApp : NSWorkspace.shared.frontmostApplication
    }

    func toggleClipboard() {
        isVisible ? hidePalette() : showClipboard()
    }

    func showClipboard() {
        palette.prepare()
        windowController.show()
    }

    func hidePalette(restoreFocus: Bool = true) {
        windowController.hide(restoreFocus: restoreFocus)
    }
}
