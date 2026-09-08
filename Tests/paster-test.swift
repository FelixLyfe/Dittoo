import AppKit

// Keep these platform dependencies inert; every test uses a private pasteboard and injected delivery.
enum ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("io.github.felixlyfe.Dittoo.internal")
}

enum Permissions {
    static func isAccessibilityTrusted() -> Bool { false }
}

@MainActor
private final class DeliveryProbe {
    var trusted = true
    var available = true
    var activates = true
    var posts = true
    var waits = true
    var frontmost: pid_t? = NSRunningApplication.current.processIdentifier
    var steps: [String] = []
    var afterWait: (() -> Void)?
    var postedPID: pid_t?

    var environment: Paster.Environment {
        Paster.Environment(
            hasAccessibility: { self.steps.append("permission"); return self.trusted },
            isAvailable: { _ in self.available },
            activate: { _ in self.steps.append("activate"); return self.activates },
            frontmostPID: { self.frontmost },
            wait: { _ in self.steps.append("wait"); self.afterWait?(); return self.waits },
            post: { pid in self.steps.append("post"); self.postedPID = pid; return self.posts })
    }
}

@main
@MainActor
struct PasterTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Dittoo-paster-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardStore(directory: root)
        store.addText("saved item", sourceBundleID: nil)
        let item = store.items[0]
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let target = NSRunningApplication.current

        let denied = DeliveryProbe()
        denied.trusted = false
        let deniedResult = await Paster.paste(item, store: store, previousApp: target,
            pasteboard: pasteboard, environment: denied.environment,
            beforePaste: { denied.steps.append("hide") })
        expect(deniedResult == .copied(.accessibility), "permission denial reports copied-only")
        expect(denied.steps == ["permission"], "permission denial never hides, activates, waits, or posts")
        expect(pasteboard.string(forType: .string) == item.text, "manual paste remains available after denial")
        expect(pasteboard.types?.contains(ClipboardManager.internalType) == true, "copies retain the internal marker")

        let granted = DeliveryProbe()
        let delivered = await Paster.paste(item, store: store, previousApp: target,
            pasteboard: pasteboard, environment: granted.environment,
            beforePaste: { granted.steps.append("hide") })
        expect(delivered == .posted, "a granted retry posts successfully")
        expect(granted.steps == ["permission", "hide", "activate", "wait", "permission", "post"],
            "permission and copying precede dismissal, and delivery completes before success")
        expect(granted.postedPID == target.processIdentifier, "events are addressed only to the captured target")

        let missing = DeliveryProbe()
        let noTarget = await Paster.paste(item, store: store, previousApp: nil,
            pasteboard: pasteboard, environment: missing.environment)
        expect(noTarget == .copied(.targetUnavailable), "a missing destination is not reported as a paste")
        expect(missing.steps.isEmpty, "a missing destination does not request permission or post")

        let inactive = DeliveryProbe()
        inactive.activates = false
        let activationFailure = await Paster.paste(item, store: store, previousApp: target,
            pasteboard: pasteboard, environment: inactive.environment)
        expect(activationFailure == .copied(.targetUnavailable), "activation failure is explicit")
        expect(inactive.postedPID == nil, "activation failure never posts into the foreground app")

        let inPlace = DeliveryProbe()
        inPlace.frontmost = nil
        let kept = await Paster.pasteInPlace(item, store: store, into: target,
            pasteboard: pasteboard, environment: inPlace.environment)
        expect(kept == .posted, "keeping the window open can deliver to the captured target")
        expect(!inPlace.steps.contains("activate"), "keeping the window open does not activate the target")

        let changed = DeliveryProbe()
        changed.afterWait = {
            pasteboard.clearContents()
            pasteboard.setString("a newer copy", forType: .string)
        }
        let changedResult = await Paster.paste(item, store: store, previousApp: target,
            pasteboard: pasteboard, environment: changed.environment)
        expect(changedResult == .failed(.clipboardChanged), "a concurrent clipboard change cancels delivery")
        expect(changed.postedPID == nil, "a newer clipboard value is never pasted as the chosen history item")

        let revoked = DeliveryProbe()
        revoked.afterWait = { revoked.trusted = false }
        let revokedResult = await Paster.paste(item, store: store, previousApp: target,
            pasteboard: pasteboard, environment: revoked.environment)
        expect(revokedResult == .copied(.accessibility), "revocation during activation is reported")
        expect(revoked.postedPID == nil, "revoked access prevents posting")

        let failedPost = DeliveryProbe()
        failedPost.posts = false
        let failedResult = await Paster.paste(item, store: store, previousApp: target,
            pasteboard: pasteboard, environment: failedPost.environment)
        expect(failedResult == .copied(.eventUnavailable), "event creation failure does not report success")

        let absent = ClipboardItem(imagePath: root.appendingPathComponent("missing.png").path, sourceBundleID: nil)
        let oldCount = pasteboard.changeCount
        let unavailable = await Paster.paste(absent, store: store, previousApp: target,
            pasteboard: pasteboard, environment: granted.environment)
        expect(unavailable == .failed(.unavailable), "a missing image reports a copy failure")
        expect(pasteboard.changeCount == oldCount, "a missing image leaves the existing clipboard untouched")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
