import Foundation
import SQLite3

// Spelled as the C macro in sqlite3.h, which isn't imported into Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct ClipboardItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case text, image }

    let id: UUID
    let kind: Kind
    let text: String?
    /// Absolute path on disk; only files under `imagesDir` are ours to delete.
    let imagePath: String?
    let createdAt: Date
    /// Bundle ID of the app frontmost when the copy was captured (see `ClipboardManager.poll`).
    let sourceBundleID: String?
    /// When the entry was pinned; pins lead the list and are exempt from pruning.
    let pinnedAt: Date?

    var isPinned: Bool { pinnedAt != nil }

    init(text: String, sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: Date(),
            sourceBundleID: sourceBundleID)
    }

    init(imagePath: String, createdAt: Date = Date(), sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .image, text: nil, imagePath: imagePath, createdAt: createdAt,
            sourceBundleID: sourceBundleID)
    }

    init(
        id: UUID, kind: Kind, text: String?, imagePath: String?, createdAt: Date,
        sourceBundleID: String?, pinnedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
        self.pinnedAt = pinnedAt
    }

    /// Copy with the two fields the store rewrites; the pin is always stated outright.
    func with(createdAt: Date? = nil, pinnedAt: Date?) -> ClipboardItem {
        ClipboardItem(
            id: id, kind: kind, text: text, imagePath: imagePath,
            createdAt: createdAt ?? self.createdAt, sourceBundleID: sourceBundleID,
            pinnedAt: pinnedAt)
    }

    /// Case-insensitive substring match: how the store filters without FTS.
    func matches(_ query: String) -> Bool {
        text?.localizedCaseInsensitiveContains(query) ?? false
    }
}

/// Retention in days; `forever` is -1, so an unset key (0) falls through to the default.
enum ClipboardRetention: Int, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case sixMonths = 180
    case year = 365
    case forever = -1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .day: return String(localized: "1 Day")
        case .week: return String(localized: "1 Week")
        case .month: return String(localized: "1 Month")
        case .threeMonths: return String(localized: "3 Months")
        case .sixMonths: return String(localized: "6 Months")
        case .year: return String(localized: "1 Year")
        case .forever: return String(localized: "Forever")
        }
    }

    var maxAge: TimeInterval {
        self == .forever ? .greatestFiniteMagnitude : TimeInterval(rawValue) * 86_400
    }
}

/// SQLite-backed clipboard history. See docs/features/clipboard.md#store.
@MainActor
@Observable
final class ClipboardStore {
    enum Failure: Equatable {
        case open, read, write, imageWrite, imageDelete

        var message: String {
            switch self {
            case .open:
                String(localized: "Clipboard history could not be opened. Your existing files have been kept.")
            case .read:
                String(localized: "Clipboard history could not be read. Please reload history and try again.")
            case .write:
                String(localized: "The last history change could not be saved. Please try the action again.")
            case .imageWrite:
                String(localized: "The clipboard image could not be saved. Please copy it again.")
            case .imageDelete:
                String(localized: "Some clipboard image files could not be removed. Please clear history again.")
            }
        }
    }

    struct SearchPage {
        let items: [ClipboardItem]
        let hasMore: Bool
    }

    static let pageSize = 200
    private(set) var failure: Failure?
    /// Captured before image conversion or writing; Clear History invalidates the whole operation.
    @ObservationIgnored private(set) var imageGeneration = UUID()

    /// Newest-first with pins in place, every pin resident. docs/features/clipboard.md
    private(set) var items: [ClipboardItem] = [] {
        didSet {
            searchCache = nil
        }
    }
    var maxAge: TimeInterval = ClipboardRetention.threeMonths.maxAge

    /// One-entry memo so repeated renders reuse the FTS result; cleared when `items` changes.
    @ObservationIgnored private var searchCache:
        (query: String, filter: ClipboardFilter, limit: Int, result: SearchPage)?

    private static let memoryWindow = 1000

    private static let schema = """
        CREATE TABLE IF NOT EXISTS items(
          id TEXT NOT NULL UNIQUE,
          kind TEXT NOT NULL,
          text TEXT,
          image_path TEXT,
          created_at REAL NOT NULL,
          source_app TEXT,
          pinned_at REAL
        );
        CREATE INDEX IF NOT EXISTS items_created_at ON items(created_at);
        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
          text, content='items', content_rowid='rowid', tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
          INSERT INTO items_fts(rowid, text) VALUES(new.rowid, new.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
          INSERT INTO items_fts(items_fts, rowid, text) VALUES('delete', old.rowid, old.text);
        END;
        """

    private let imagesDir: URL
    private let dbURL: URL
    @ObservationIgnored private var db: OpaquePointer?
    @ObservationIgnored private var insertStmt: OpaquePointer?
    @ObservationIgnored private var loadStmt: OpaquePointer?
    @ObservationIgnored private var windowFloorStmt: OpaquePointer?
    @ObservationIgnored private var searchStmt: OpaquePointer?
    @ObservationIgnored private var scanStmt: OpaquePointer?
    @ObservationIgnored private var deleteByIDStmt: OpaquePointer?
    @ObservationIgnored private var pinStmt: OpaquePointer?
    @ObservationIgnored private var staleImagesStmt: OpaquePointer?
    @ObservationIgnored private var deleteStaleStmt: OpaquePointer?

    /// `directory` defaults to durable per-channel Application Support storage.
    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        dbURL = base.appendingPathComponent("clipboard.sqlite3")
        do {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        } catch {
            failure = .open
            return
        }
        if !openDatabase() {
            // History is durable user data. Even a corrupt database must remain available for recovery.
            closeDatabase()
            failure = .open
        }
    }

    var isEmpty: Bool { items.isEmpty }

    /// Clipboard history is user data, so it belongs in Application Support rather than Caches.
    private static var defaultDirectory: URL {
        AppPaths.applicationSupport()
    }

    // Isolated so teardown may touch the main-actor pointers; the release is already on main.
    isolated deinit {
        closeDatabase()
    }

    @discardableResult
    func load() -> Bool {
        if db == nil, !openDatabase() {
            closeDatabase()
            failure = .open
            return false
        }
        guard let stmt = loadStmt, let floor = windowFloor() else { return false }
        sqlite3_bind_int64(stmt, 1, floor)
        var loaded: [ClipboardItem] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            if let item = Self.row(stmt) { loaded.append(item) }
            status = sqlite3_step(stmt)
        }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        guard status == SQLITE_DONE else {
            failure = .read
            return false
        }
        items = loaded
        failure = nil
        // Age passes while the app isn't running; insert-time pruning alone can't catch that.
        return enforceLimits()
    }

    /// Called on load and when the retention setting changes.
    @discardableResult
    func enforceLimits() -> Bool {
        prune()
    }

    /// The floor rowid `loadStmt` reads from; 0 means no floor, so load everything.
    private func windowFloor() -> sqlite3_int64? {
        guard let stmt = windowFloorStmt else { return nil }
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        sqlite3_bind_int(stmt, 1, Int32(Self.memoryWindow - 1))
        switch sqlite3_step(stmt) {
        case SQLITE_ROW: return sqlite3_column_int64(stmt, 0)
        case SQLITE_DONE: return 0
        default:
            failure = .read
            return nil
        }
    }

    @discardableResult
    func addText(_ text: String, sourceBundleID: String?) -> Bool {
        if items.first?.kind == .text, items.first?.text == text { return true }
        return insert(ClipboardItem(text: text, sourceBundleID: sourceBundleID))
    }

    @discardableResult
    func addImage(_ data: Data, sourceBundleID: String?, generation: UUID? = nil) -> Task<Void, Never>? {
        let generation = generation ?? imageGeneration
        guard generation == imageGeneration, databaseReady() else { return nil }
        let url = imagesDir.appendingPathComponent(UUID().uuidString + ".png")
        let item = ClipboardItem(imagePath: url.path, sourceBundleID: sourceBundleID)
        // The blob write is multi-MB I/O; only the row insert returns to the main actor.
        return Task.detached(priority: .utility) { [weak self] in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                await self?.imageWriteFailed(generation: generation)
                return
            }
            guard let self else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            await self.finishImage(item, generation: generation)
        }
    }

    private func imageWriteFailed(generation: UUID) {
        if generation == imageGeneration { failure = .imageWrite }
    }

    private func finishImage(_ item: ClipboardItem, generation: UUID) {
        guard generation == imageGeneration, insert(item) else {
            deleteBlob(item)
            return
        }
    }

    /// Move an item to the top; pasting or copying it from the palette re-recencies it.
    @discardableResult
    func promote(_ item: ClipboardItem) -> Bool {
        // A pinned row holds its place, so re-recencying it would rewrite for no change.
        guard !item.isPinned, items.first?.id != item.id else { return true }
        return reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    @discardableResult
    func togglePinned(_ item: ClipboardItem) -> Bool {
        item.isPinned ? unpin(item) : pin(item)
    }

    @discardableResult
    func remove(_ item: ClipboardItem) -> Bool {
        guard databaseReady(), let stmt = deleteByIDStmt else { return false }
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        guard stepWrite(stmt) else { return false }
        failure = nil
        items.removeAll { $0.id == item.id }
        deleteBlob(item)
        return true
    }

    @discardableResult
    func clearAll() -> Bool {
        guard databaseReady(), executeWrite("DELETE FROM items") else { return false }
        imageGeneration = UUID()
        failure = nil
        items = []
        do {
            if FileManager.default.fileExists(atPath: imagesDir.path) {
                try FileManager.default.removeItem(at: imagesDir)
            }
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            return true
        } catch {
            failure = .imageDelete
            return false
        }
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let path = item.imagePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Display order for `query` under `filter`: pinned entries first, each block newest-first.
    func search(_ query: String, filter: ClipboardFilter, limit: Int = 1000) -> [ClipboardItem] {
        searchPage(query, filter: filter, limit: limit).items
    }

    func searchPage(_ query: String, filter: ClipboardFilter, limit: Int = 1000) -> SearchPage {
        _ = items  // A cache hit must still participate in SwiftUI's observation of history changes.
        let q = query.trimmingCharacters(in: .whitespaces)
        let limit = max(1, limit)
        if let searchCache, searchCache.query == q, searchCache.filter == filter,
            searchCache.limit == limit
        {
            return searchCache.result
        }
        // Every pin stays resident; ordinary history pages are read from disk, even for short queries.
        let pins = pinnedItems.filter { filter.matches($0) && (q.isEmpty || $0.matches(q)) }
        let usesFTS = q.count >= 3
        guard let stmt = usesFTS ? searchStmt : scanStmt else {
            return SearchPage(items: pins, hasMore: false)
        }
        if usesFTS {
            let match = "\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
        } else if filter == .image {
            sqlite3_bind_text(stmt, 1, "image", -1, SQLITE_TRANSIENT)
        } else if filter != .all || !q.isEmpty {
            sqlite3_bind_text(stmt, 1, "text", -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        var history: [ClipboardItem] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            if let item = Self.row(stmt), filter.matches(item),
                usesFTS || q.isEmpty || item.matches(q)
            {
                // Apply the type filter before counting, so other types cannot crowd out a match.
                if history.count == limit { break }
                history.append(item)
            }
            status = sqlite3_step(stmt)
        }
        guard status == SQLITE_ROW || status == SQLITE_DONE else {
            failure = .read
            return SearchPage(items: pins, hasMore: false)
        }
        let result = SearchPage(items: pins + history, hasMore: status == SQLITE_ROW)
        searchCache = (q, filter, limit, result)
        return result
    }

    /// Row index of `item` as currently listed, so the palette can follow a row that moved.
    func rowIndex(of item: ClipboardItem, in query: String, filter: ClipboardFilter) -> Int? {
        search(query, filter: filter).firstIndex { $0.id == item.id }
    }

    // MARK: - Private

    /// The Pinned section in pin order, so a new pin joins the end rather than the head.
    private var pinnedItems: [ClipboardItem] {
        items.filter(\.isPinned)
            .sorted { ($0.pinnedAt ?? .distantFuture) < ($1.pinnedAt ?? .distantFuture) }
    }

    /// The row keeps its place and gains a stamp, which heads the Pinned section.
    private func pin(_ item: ClipboardItem) -> Bool {
        guard databaseReady(), let stmt = pinStmt else { return false }
        let stamp = Date()
        let pinned = item.with(pinnedAt: stamp)
        sqlite3_bind_double(stmt, 1, stamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, item.id.uuidString, -1, SQLITE_TRANSIENT)
        guard stepWrite(stmt) else { return false }
        failure = nil
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = pinned
        } else {
            // Pinned from an FTS hit outside the window, so splice it in by recency.
            let index = items.firstIndex { $0.createdAt < pinned.createdAt } ?? items.count
            items.insert(pinned, at: index)
        }
        return true
    }

    /// Unpinning rejoins as the newest entry. See docs/features/clipboard.md#pinned-entries.
    private func unpin(_ item: ClipboardItem) -> Bool {
        reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    /// Rewrite a row under the same id so it leads. See docs/features/clipboard.md#store.
    private func reinsert(_ updated: ClipboardItem) -> Bool {
        guard databaseReady(), let deleteStmt = deleteByIDStmt, let insertStmt else { return false }
        let committed = transaction {
            sqlite3_bind_text(deleteStmt, 1, updated.id.uuidString, -1, SQLITE_TRANSIENT)
            return stepWrite(deleteStmt) && bindAndInsert(insertStmt, updated)
        }
        guard committed else { return false }
        failure = nil
        // Array ops also cover items surfaced by FTS from beyond the in-memory window.
        items.removeAll { $0.id == updated.id }
        items.insert(updated, at: 0)
        trimWindow()
        return true
    }

    /// Cap the in-memory window, but never drop a pinned row: those render however old they are.
    private func trimWindow() {
        guard items.lazy.filter({ !$0.isPinned }).count > Self.memoryWindow,
            let index = items.lastIndex(where: { !$0.isPinned })
        else { return }
        items.remove(at: index)
    }

    private func insert(_ item: ClipboardItem) -> Bool {
        guard databaseReady(), let stmt = insertStmt, bindAndInsert(stmt, item) else { return false }
        failure = nil
        items.insert(item, at: 0)
        trimWindow()
        _ = prune()
        return true
    }

    private func bindAndInsert(_ stmt: OpaquePointer, _ item: ClipboardItem) -> Bool {
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, item.kind.rawValue, -1, SQLITE_TRANSIENT)
        if let text = item.text {
            sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        if let path = item.imagePath {
            sqlite3_bind_text(stmt, 4, path, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_double(stmt, 5, item.createdAt.timeIntervalSince1970)
        if let source = item.sourceBundleID {
            sqlite3_bind_text(stmt, 6, source, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        if let pinnedAt = item.pinnedAt {
            sqlite3_bind_double(stmt, 7, pinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        return stepWrite(stmt)
    }

    /// Whether a path is inside our images directory; only those are ours to delete.
    private func owns(_ path: String) -> Bool {
        path.hasPrefix(imagesDir.path + "/")
    }

    private func prune() -> Bool {
        guard databaseReady(), let imagesStmt = staleImagesStmt, let deleteStmt = deleteStaleStmt else {
            return false
        }
        let cutoff = Date().addingTimeInterval(-maxAge)
        var staleOwnedPaths: [String] = []
        let committed = transaction {
            sqlite3_bind_double(imagesStmt, 1, cutoff.timeIntervalSince1970)
            var status = sqlite3_step(imagesStmt)
            while status == SQLITE_ROW {
                // Only delete files we own; an external reference just loses its row.
                if let path = Self.columnString(imagesStmt, 0), owns(path) {
                    staleOwnedPaths.append(path)
                }
                status = sqlite3_step(imagesStmt)
            }
            sqlite3_reset(imagesStmt)
            sqlite3_clear_bindings(imagesStmt)
            guard status == SQLITE_DONE else { return false }
            sqlite3_bind_double(deleteStmt, 1, cutoff.timeIntervalSince1970)
            return stepWrite(deleteStmt)
        }
        guard committed else { return false }
        searchCache = nil
        // Delete blobs only after their rows are durably removed.
        if !staleOwnedPaths.isEmpty {
            let paths = staleOwnedPaths
            Task.detached(priority: .utility) { [weak self] in
                for path in paths where FileManager.default.fileExists(atPath: path) {
                    do {
                        try FileManager.default.removeItem(atPath: path)
                    } catch {
                        if (error as? CocoaError)?.code != .fileNoSuchFile {
                            await self?.imageDeletionFailed()
                        }
                    }
                }
            }
        }
        // Against the oldest unpinned row: an exempt pin would make this permanently true.
        if items.last(where: { !$0.isPinned }).map({ $0.createdAt < cutoff }) == true {
            items.removeAll { $0.createdAt < cutoff && !$0.isPinned }
        }
        return true
    }

    private func deleteBlob(_ item: ClipboardItem) {
        guard let path = item.imagePath, owns(path), FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            if (error as? CocoaError)?.code != .fileNoSuchFile { imageDeletionFailed() }
        }
    }

    private func imageDeletionFailed() { failure = .imageDelete }

    private func databaseReady() -> Bool {
        db != nil || load()
    }

    private func stepWrite(_ stmt: OpaquePointer) -> Bool {
        let status = sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        guard status == SQLITE_DONE else {
            failure = .write
            return false
        }
        return true
    }

    private func executeWrite(_ sql: String) -> Bool {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            failure = .write
            return false
        }
        return true
    }

    private func transaction(_ body: () -> Bool) -> Bool {
        guard executeWrite("BEGIN IMMEDIATE") else { return false }
        guard body(), executeWrite("COMMIT") else {
            if sqlite3_get_autocommit(db) == 0,
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil) != SQLITE_OK { closeDatabase() }
            failure = .write
            return false
        }
        return true
    }

    private func openDatabase() -> Bool {
        guard
            sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
                == SQLITE_OK,
            sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
                == SQLITE_OK
        else { return false }
        let hadFTS = columnExists("text", in: "items_fts")
        let schemaReady = transaction {
            guard executeWrite(Self.schema) else { return false }
            if !columnExists("source_app", in: "items"),
                !executeWrite("ALTER TABLE items ADD COLUMN source_app TEXT") { return false }
            if !columnExists("pinned_at", in: "items"),
                !executeWrite("ALTER TABLE items ADD COLUMN pinned_at REAL") { return false }
            guard executeWrite(
                "CREATE INDEX IF NOT EXISTS items_pinned_at ON items(pinned_at) WHERE pinned_at IS NOT NULL"
            ) else { return false }
            return hadFTS || executeWrite("INSERT INTO items_fts(items_fts) VALUES('rebuild')")
        }
        guard schemaReady else { return false }
        insertStmt = prepare(
            """
            INSERT INTO items(id, kind, text, image_path, created_at, source_app, pinned_at)
            VALUES(?,?,?,?,?,?,?)
            """
        )
        // Two indexed branches, deliberately not one OR. See docs/features/clipboard.md#store.
        loadStmt = prepare(
            """
            SELECT id, kind, text, image_path, created_at, source_app, pinned_at FROM (
              SELECT rowid AS rid, * FROM items WHERE rowid >= ?1
              UNION ALL
              SELECT rowid AS rid, * FROM items WHERE pinned_at IS NOT NULL AND rowid < ?1
            ) ORDER BY rid DESC
            """)
        windowFloorStmt = prepare(
            "SELECT rowid FROM items WHERE pinned_at IS NULL ORDER BY rowid DESC LIMIT 1 OFFSET ?")
        searchStmt = prepare(
            """
            SELECT i.id, i.kind, i.text, i.image_path, i.created_at, i.source_app, i.pinned_at
            FROM items_fts f JOIN items i ON i.rowid = f.rowid
            WHERE items_fts MATCH ? AND i.pinned_at IS NULL ORDER BY f.rowid DESC
            """)
        scanStmt = prepare(
            """
            SELECT id, kind, text, image_path, created_at, source_app, pinned_at
            FROM items WHERE pinned_at IS NULL AND (?1 IS NULL OR kind = ?1) ORDER BY rowid DESC
            """)
        deleteByIDStmt = prepare("DELETE FROM items WHERE id = ?")
        // Only ever sets a stamp: unpinning rewrites the whole row so it leads the history again.
        pinStmt = prepare("UPDATE items SET pinned_at = ? WHERE id = ?")
        staleImagesStmt = prepare(
            """
            SELECT image_path FROM items
            WHERE created_at < ? AND pinned_at IS NULL AND image_path IS NOT NULL
            """)
        deleteStaleStmt = prepare("DELETE FROM items WHERE created_at < ? AND pinned_at IS NULL")
        return insertStmt != nil && loadStmt != nil && windowFloorStmt != nil && searchStmt != nil && scanStmt != nil
            && deleteByIDStmt != nil && pinStmt != nil && staleImagesStmt != nil
            && deleteStaleStmt != nil
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private func columnExists(_ column: String, in table: String) -> Bool {
        guard let stmt = prepare("PRAGMA table_info(\(table))") else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1), String(cString: c) == column { return true }
        }
        return false
    }

    private func closeDatabase() {
        [
            insertStmt, loadStmt, windowFloorStmt, searchStmt, scanStmt, deleteByIDStmt, pinStmt,
            staleImagesStmt, deleteStaleStmt
        ].forEach { sqlite3_finalize($0) }
        insertStmt = nil
        loadStmt = nil
        windowFloorStmt = nil
        searchStmt = nil
        scanStmt = nil
        deleteByIDStmt = nil
        pinStmt = nil
        staleImagesStmt = nil
        deleteStaleStmt = nil
        sqlite3_close_v2(db)
        db = nil
    }

    private static func row(_ stmt: OpaquePointer?) -> ClipboardItem? {
        guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
            let kindString = columnString(stmt, 1),
            let kind = ClipboardItem.Kind(rawValue: kindString)
        else { return nil }
        return ClipboardItem(
            id: id, kind: kind, text: columnString(stmt, 2), imagePath: columnString(stmt, 3),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            sourceBundleID: columnString(stmt, 5), pinnedAt: columnDate(stmt, 6))
    }

    private static func columnDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    private static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }
}
