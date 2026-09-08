import AppKit
import Synchronization

/// SwiftUI tracks this observable generation when an icon request is built in `body`.
@MainActor
@Observable
final class IconStyleSignal {
    private(set) var generation = 0

    fileprivate func bump() { generation &+= 1 }
}

struct IconRequest<Key: Hashable>: Hashable {
    let key: Key
    let generation: Int

    @MainActor
    init(_ key: Key) {
        self.key = key
        generation = IconCache.style.generation
    }
}

/// App icons by path, downsampled and byte-bounded so clipboard rows do not re-hit NSWorkspace.
enum IconCache {
    private final class Cache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    private static let displayPixel: CGFloat = 48
    private static let cache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    private static let darkSurface = Mutex(true)
    private static let styleGeneration = Mutex(0)

    @MainActor static let style = IconStyleSignal()

    static func cached(forFile path: String) -> NSImage? {
        cache.object(forKey: fileKey(path))
    }

    @MainActor static func observeStyle() { _ = style.generation }

    @MainActor static func setDarkSurface(_ isDark: Bool) {
        let changed = darkSurface.withLock { surface -> Bool in
            defer { surface = isDark }
            return surface != isDark
        }
        if changed { invalidateStyled() }
    }

    @MainActor static func invalidateStyled() {
        styleGeneration.withLock { $0 &+= 1 }
        cache.removeAllObjects()
        style.bump()
    }

    static func styleFingerprint() -> Data? {
        let side = 32
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
            .draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let bytes = rep.bitmapData else { return nil }
        return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    static func loadAsync(forFile path: String) async -> NSImage? {
        if let cached = cached(forFile: path) { return cached }
        return await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return icon(forFile: path)
        }.value
    }

    static func icon(forFile path: String) -> NSImage {
        let key = fileKey(path)
        if let cached = cache.object(forKey: key) { return cached }
        let (icon, cost) = downsampled(NSWorkspace.shared.icon(forFile: path))
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    private static func fileKey(_ path: String) -> NSString {
        "\(styleGeneration.withLock { $0 }):file:\(path)" as NSString
    }

    private static func downsampled(_ source: NSImage) -> (NSImage, Int) {
        let pixels = Int(displayPixel * 2)
        let fallbackCost = Int(displayPixel * displayPixel * 4)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return (source, fallbackCost) }
        rep.size = NSSize(width: displayPixel, height: displayPixel)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: rep.size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return (image, rep.bytesPerRow * rep.pixelsHigh)
    }
}
