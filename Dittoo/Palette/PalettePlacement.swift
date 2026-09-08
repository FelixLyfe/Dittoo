import CoreGraphics

/// Where the palette's top-left corner sits. Pure, with every screen fact injected, so the window
/// controller holds no placement maths of its own and this stays testable off a display.
enum PalettePlacement {
    /// The untouched placement: centred, top edge a fraction of the way down, growing downward.
    static func defaultAnchor(
        in visibleFrame: CGRect, width: CGFloat, topMarginFraction: CGFloat
    )
        -> CGPoint
    {
        CGPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.maxY - visibleFrame.height * topMarginFraction)
    }
}
