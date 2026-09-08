import AppKit
import Foundation

@main
@MainActor
struct IconCacheTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        let path = "/System/Library/CoreServices/Finder.app"
        let before = IconCache.style.generation
        let warm = IconCache.icon(forFile: path)
        expect(IconCache.cached(forFile: path) === warm, "a decoded app icon is cached")

        IconCache.invalidateStyled()
        expect(IconCache.style.generation == before + 1, "a restyle moves the generation")
        expect(IconCache.cached(forFile: path) == nil, "a restyle drops cached icons")
        expect(IconRequest("finder").generation == IconCache.style.generation, "requests carry it")
        expect(IconRequest("finder") != IconRequest("mail"), "request keys remain distinct")

        let fingerprint = IconCache.styleFingerprint()
        expect(fingerprint != nil, "the style probe renders")
        expect(fingerprint == IconCache.styleFingerprint(), "an unchanged style is stable")

        print(failures == 0 ? "Icon cache tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
