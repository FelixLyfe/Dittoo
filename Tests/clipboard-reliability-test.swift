import Foundation
import SQLite3

@main
@MainActor
struct ClipboardReliabilityTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dittoo-reliability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try lockedStartup(root.appendingPathComponent("startup"))
        try corruptStartup(root.appendingPathComponent("corrupt"))
        try failedWrites(root.appendingPathComponent("writes"))
        try transactionRollback(root.appendingPathComponent("rollback"))
        try await failedImageDeletion(root.appendingPathComponent("deletion"))
        try await clearDuringImageWrite(root.appendingPathComponent("images"))
        await fullHistorySearch(root.appendingPathComponent("search"))
        filterBeforeLimit(root.appendingPathComponent("filter"))
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func execute(_ db: OpaquePointer, _ sql: String) {
        precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "fixture SQL failed")
    }

    static func connect(_ directory: URL) throws -> OpaquePointer {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var db: OpaquePointer?
        let url = directory.appendingPathComponent("clipboard.sqlite3")
        precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
        return db!
    }

    static func lockedStartup(_ directory: URL) throws {
        let db = try connect(directory)
        defer { sqlite3_close(db) }
        execute(db, """
            CREATE TABLE items(id TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, text TEXT,
              image_path TEXT, created_at REAL NOT NULL, source_app TEXT, pinned_at REAL);
            INSERT INTO items VALUES('\(UUID().uuidString)', 'text', 'kept history', NULL,
              \(Date().timeIntervalSince1970), NULL, NULL);
            BEGIN EXCLUSIVE;
            """)
        let store = ClipboardStore(directory: directory)
        expect(store.failure == .open, "a startup failure is visible")
        execute(db, "ROLLBACK;")
        store.load()
        expect(store.failure == nil, "a reload recovers after a transient lock")
        let reopened = ClipboardStore(directory: directory)
        reopened.load()
        expect(reopened.items.first?.text == "kept history", "a locked valid database is preserved")
        expect(reopened.search("kept", filter: .all).count == 1, "an old database gains a complete search index")
    }

    static func corruptStartup(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("clipboard.sqlite3")
        let original = Data("unreadable database fixture".utf8)
        try original.write(to: url)
        let store = ClipboardStore(directory: directory)
        store.load()
        let remaining = try Data(contentsOf: url)
        expect(remaining == original, "unreadable database bytes are preserved for recovery")
        expect(store.failure == .open, "unreadable history is not silently presented as a fresh store")
    }

    static func failedWrites(_ directory: URL) throws {
        let store = ClipboardStore(directory: directory)
        store.addText("saved", sourceBundleID: nil)
        store.addText("saved newest", sourceBundleID: nil)
        let saved = store.items.last!
        let db = try connect(directory)
        defer { sqlite3_close(db) }
        execute(db, "BEGIN IMMEDIATE;")
        store.addText("not saved", sourceBundleID: nil)
        expect(store.failure == .write, "failed writes expose a persistence error")
        expect(!store.items.contains { $0.text == "not saved" }, "failed inserts do not appear saved")
        store.togglePinned(saved)
        expect(store.items.first { $0.id == saved.id }?.isPinned == false, "failed pins do not change the UI")
        store.remove(saved)
        expect(store.items.contains { $0.id == saved.id }, "failed deletes preserve visible history")
        store.clearAll()
        expect(store.items.count == 2, "failed clears preserve visible history")
        execute(db, "ROLLBACK;")
        store.load()
        expect(store.items.count == 2, "failed writes leave persisted history unchanged")
        expect(store.addText("retried", sourceBundleID: nil), "writing can recover after the lock is released")
        expect(store.failure == nil, "a successful retry clears the write error")
    }

    static func transactionRollback(_ directory: URL) throws {
        let store = ClipboardStore(directory: directory)
        store.addText("original", sourceBundleID: nil)
        store.addText("newest", sourceBundleID: nil)
        store.load()
        let original = store.items.last!
        let before = store.items
        let db = try connect(directory)
        defer { sqlite3_close(db) }
        execute(db, """
            CREATE TRIGGER reject_promotion BEFORE INSERT ON items WHEN new.text = 'original'
            BEGIN SELECT RAISE(ABORT, 'fixture rejection'); END;
            """)
        expect(!store.promote(original), "a failed insert does not report successful promotion")
        expect(store.items == before, "a failed promotion preserves visible ordering")
        store.load()
        expect(store.items == before, "a failed promotion rolls back the preceding delete")
    }

    static func failedImageDeletion(_ directory: URL) async throws {
        let store = ClipboardStore(directory: directory)
        let pending = store.addImage(Data([0x89, 0x50, 0x4E, 0x47]), sourceBundleID: nil)
        await pending?.value
        let path = URL(fileURLWithPath: store.items.first!.imagePath!)
        let db = try connect(directory)
        defer { sqlite3_close(db) }
        let old = Date().addingTimeInterval(-2 * 86_400).timeIntervalSince1970
        execute(db, "UPDATE items SET created_at = \(old);")
        store.load()
        let image = store.items.first!
        execute(db, "BEGIN IMMEDIATE;")
        store.remove(image)
        expect(FileManager.default.fileExists(atPath: path.path), "failed deletion keeps its image bytes")
        store.clearAll()
        expect(FileManager.default.fileExists(atPath: path.path), "failed clear keeps image bytes")
        store.maxAge = 86_400
        store.enforceLimits()
        expect(store.items.count == 1, "failed retention pruning keeps its visible row")
        expect(FileManager.default.fileExists(atPath: path.path), "failed retention pruning keeps image bytes")
        execute(db, "ROLLBACK;")
    }

    static func clearDuringImageWrite(_ directory: URL) async throws {
        let store = ClipboardStore(directory: directory)
        let generation = store.imageGeneration
        let pending = store.addImage(Data(repeating: 0xAA, count: 4096), sourceBundleID: nil)
        let images = directory.appendingPathComponent("images")
        // File I/O completes while its MainActor row insert remains queued behind this action.
        let deadline = Date().addingTimeInterval(2)
        while try FileManager.default.contentsOfDirectory(atPath: images.path)
            .filter({ $0.hasSuffix(".png") }).isEmpty, Date() < deadline { usleep(1000) }
        let written = try FileManager.default.contentsOfDirectory(atPath: images.path)
        expect(
            written.contains { $0.hasSuffix(".png") },
            "the pending image write reached disk")
        store.clearAll()
        await pending?.value
        expect(store.items.isEmpty, "clear invalidates a queued image insert")
        let reopened = ClipboardStore(directory: directory)
        reopened.load()
        expect(reopened.items.isEmpty, "cleared images do not return after reopening")
        let files = try FileManager.default.contentsOfDirectory(atPath: images.path)
        expect(files.isEmpty, "clear leaves no pending image blobs")
        let lateConversion = store.addImage(Data([1]), sourceBundleID: nil, generation: generation)
        await lateConversion?.value
        expect(store.items.isEmpty, "clear also invalidates conversion started before the clear")
        let fresh = store.addImage(Data([2]), sourceBundleID: nil)
        await fresh?.value
        expect(store.items.count == 1, "copies started after the clear can still be saved")
    }

    static func fullHistorySearch(_ directory: URL) async {
        let store = ClipboardStore(directory: directory)
        store.addText("客户资料", sourceBundleID: nil)
        let pending = store.addImage(Data([0x89, 0x50, 0x4E, 0x47]), sourceBundleID: nil)
        await pending?.value
        for index in 0..<1001 {
            store.addText("filler \(index)", sourceBundleID: nil)
        }
        store.load()
        expect(store.search("客户", filter: .all).count == 1, "short Chinese searches cover old history")
        expect(store.search("客户资", filter: .all).count == 1, "FTS still finds old history")
        expect(store.search("", filter: .image).count == 1, "image filters cover old history")
        let page = store.searchPage("", filter: .all, limit: 200)
        expect(page.items.count == 200 && page.hasMore, "the browser starts with a bounded page")
        let complete = store.searchPage("", filter: .all, limit: 1200)
        expect(complete.items.count == 1003 && !complete.hasMore, "pagination reaches all retained history")
    }

    static func filterBeforeLimit(_ directory: URL) {
        let store = ClipboardStore(directory: directory)
        store.addText("https://needle.example.com", sourceBundleID: nil)
        for index in 1...200 {
            store.addText("needle prose \(index)", sourceBundleID: nil)
        }
        expect(store.search("needle", filter: .link).count == 1, "classification precedes the result limit")
    }
}
