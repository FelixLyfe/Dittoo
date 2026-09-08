import AppKit
import SwiftUI

@MainActor
final class PaletteWindowController: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panel: PalettePanel?
    private(set) var previousApp: NSRunningApplication?
    private weak var previousOwnWindow: NSWindow?

    init(core: AppCore) {
        self.core = core
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        Signposts.interval("PaletteWindowController.show") {
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier {
                previousApp = nil
                if let key = NSApp.keyWindow, key !== panel { previousOwnWindow = key }
            } else {
                previousApp = frontmost
                previousOwnWindow = nil
            }
            core.palette.pasteTarget = PasteTarget(app: previousApp)
            core.palette.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
            let panel = ensurePanel()
            position(panel)
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            DispatchQueue.main.async { [weak panel] in
                guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    func hide(restoreFocus: Bool) {
        panel?.orderOut(nil)
        ImageThumbnail.purgePreviews()
        guard restoreFocus else { return }
        if let own = previousOwnWindow, own.isVisible {
            own.makeKeyAndOrderFront(nil)
        } else {
            previousApp?.activate()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else { return }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            core.palette.focusToken = UUID()
            panel?.trackComposition()
        }
    }

    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }
        let root = RootPaletteView()
            .environment(core)
            .environment(core.settings)
            .environment(core.palette)
            .environment(core.clipboardStore)
        let panel = PalettePanel(rootView: root)
        panel.delegate = self
        panel.paletteState = core.palette
        panel.onCommandShortcut = { [weak self] event in
            guard let self, !event.isARepeat,
                event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
                let character = event.charactersIgnoringModifiers?.lowercased()
            else { return false }
            switch character {
            case ",":
                core.settingsCoordinator.showSettings()
                return true
            case ".":
                core.palette.notePinChord()
                return true
            case "w":
                core.paletteCoordinator.hidePalette()
                return true
            default:
                return false
            }
        }
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.underCursor ?? NSScreen.primary else { return }
        let anchor = PalettePlacement.defaultAnchor(
            in: screen.visibleFrame, width: Theme.Size.panelWidth,
            topMarginFraction: Theme.Size.paletteTopMarginFraction)
        panel.setFrame(
            NSRect(
                x: anchor.x, y: anchor.y - Theme.Size.panelHeight,
                width: Theme.Size.panelWidth, height: Theme.Size.panelHeight),
            display: true)
    }
}
