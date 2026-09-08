import AppKit

/// Owns clipboard-history actions: paste, copy, reveal, pin — and the selection that follows.
@MainActor
final class ClipboardCoordinator {
    private let clipboardStore: ClipboardStore
    private let palette: PaletteState
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    /// Dialogs, for the one action here that can't be undone.
    private unowned let core: AppCore
    private var isPasting = false

    init(
        clipboardStore: ClipboardStore,
        palette: PaletteState,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.clipboardStore = clipboardStore
        self.palette = palette
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// The setting names an age, the store enforces it; a shortened window culls straight away.
    func applyRetention(_ retention: ClipboardRetention) {
        clipboardStore.maxAge = retention.maxAge
        clipboardStore.enforceLimits()
    }

    func paste(_ item: ClipboardItem) {
        performPaste(item, keepWindowOpen: false)
    }

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        performPaste(item, keepWindowOpen: true)
    }

    private func performPaste(_ item: ClipboardItem, keepWindowOpen: Bool) {
        guard !isPasting else { return }
        isPasting = true
        let previous = windowController.previousApp
        Task {
            defer { isPasting = false }
            let result = await Paster.paste(
                item, store: clipboardStore, previousApp: previous, keepWindowOpen: keepWindowOpen,
                beforePaste: {
                    if !keepWindowOpen { self.paletteCoordinator.hidePalette(restoreFocus: false) }
                })
            if result.didCopy { selectClip(item) }
            await reportPasteResult(result)
        }
    }

    private func reportPasteResult(_ result: Paster.Result) async {
        switch result {
        case .posted, .failed(.cancelled): return
        case .copied(let reason):
            let message: String
            switch reason {
            case .accessibility:
                message = String(localized:
                    "The item is copied. Press ⌘V in the destination app, or grant Accessibility access and try pasting again.")
            case .targetUnavailable:
                message = String(localized:
                    "The item is copied, but the destination app is unavailable. Switch to the destination app and press ⌘V.")
            case .eventUnavailable:
                message = String(localized:
                    "The item is copied, but automatic paste could not be started. Press ⌘V in the destination app.")
            }
            let openSettings = await core.reportFailure(
                title: String(localized: "Copied to Clipboard"), message: message,
                symbol: "doc.on.clipboard",
                recovery: reason == .accessibility ? String(localized: "Open Accessibility Settings") : nil)
            if openSettings, reason == .accessibility {
                Permissions.ensureAccessibility()
                Permissions.openAccessibilitySettings()
            }
        case .failed(let failure):
            let message = failure == .clipboardChanged
                ? String(localized: "The clipboard changed before pasting. Select the entry and try again.")
                : String(localized: "The clipboard item could not be copied. Please select another entry or copy it again.")
            _ = await core.reportFailure(
                title: String(localized: "Could Not Paste"), message: message,
                symbol: "doc.on.clipboard", recovery: nil)
        }
    }

    /// Both the ⌃⇧X chord and the menu row land here, so neither can skip the confirmation.
    func deleteAllClips() async {
        guard
            await core.confirm(
                title: String(localized: "Clear clipboard history?"),
                message: String(
                    localized: "Every entry goes, pinned ones included. This can't be undone."),
                symbol: PaletteMode.clipboard.systemImage,
                confirmTitle: String(localized: "Clear History"))
        else { return }
        clipboardStore.clearAll()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        if Paster.copy(item, store: clipboardStore) {
            selectClip(item)
            paletteCoordinator.hidePalette(restoreFocus: false)
        } else {
            Task {
                _ = await core.reportFailure(
                    title: String(localized: "Could Not Copy"),
                    message: String(localized:
                        "The clipboard item could not be copied. Please select another entry or copy it again."),
                    symbol: "doc.on.clipboard", recovery: nil)
            }
        }
    }

    func revealClipboardImage(_ item: ClipboardItem) {
        guard let url = clipboardStore.imageURL(for: item) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Pin or unpin an entry; the selection and scroll follow the row as it moves.
    func togglePinnedClip(_ item: ClipboardItem) {
        guard clipboardStore.togglePinned(item) else { return }
        selectClip(item)
        palette.followToken = UUID()
    }

    /// Select `item`'s row as currently filtered; a moved row isn't always index 0.
    private func selectClip(_ item: ClipboardItem) {
        palette.selection =
            clipboardStore.rowIndex(
                of: item, in: palette.query, filter: palette.clipboardFilter) ?? 0
    }
}
