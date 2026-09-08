import Foundation

/// State shared between the clipboard panel's AppKit and SwiftUI halves.
@MainActor
@Observable
final class PaletteState {
    var query = ""
    var selection = 0
    var isComposing = false
    var clipboardFilter: ClipboardFilter = .all
    var clipboardResultLimit = ClipboardStore.pageSize
    var focusToken = UUID()
    var resetToken = UUID()
    var followToken = UUID()
    private(set) var pinChordToken = UUID()
    var pasteTarget: PasteTarget?
    @ObservationIgnored private(set) var hoverHighlightArmed = false
    private(set) var hoverDisarmToken = UUID()
    @ObservationIgnored private var hoverAnchor: CGPoint = .zero
    @ObservationIgnored var searchFieldFrame: CGRect = .zero
    @ObservationIgnored var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    @ObservationIgnored var onMenuOpenChanged: ((Bool) -> Void)?

    func prepare() {
        query = ""
        selection = 0
        isComposing = false
        clipboardFilter = .all
        clipboardResultLimit = ClipboardStore.pageSize
        dropHoverHighlight()
        menuOpen = false
        focusToken = UUID()
        resetToken = UUID()
    }

    func notePinChord() {
        pinChordToken = UUID()
    }

    func notePointerMoved(to location: CGPoint) {
        guard !hoverHighlightArmed, HoverArming.isDeliberate(location, from: hoverAnchor) else {
            return
        }
        hoverHighlightArmed = true
    }

    func disarmHoverHighlight(pointerAt location: CGPoint) {
        hoverAnchor = location
        dropHoverHighlight()
    }

    private func dropHoverHighlight() {
        guard hoverHighlightArmed else { return }
        hoverHighlightArmed = false
        hoverDisarmToken = UUID()
    }
}
