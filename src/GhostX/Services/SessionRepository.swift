import Foundation
import SQLite3

// TRANSIENT is a C macro, not imported to Swift
private let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Session persistence using SQLite (with SQLCipher for encryption in production)
final class SessionRepository: ObservableObject {
    @Published private(set) var sessions: [SessionConfig] = []
    @Published private(set) var groups: [SessionGroup] = []

    private var db: OpaquePointer?
    private let dbPath: String

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("GhostX")
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        dbPath = dbDir.appendingPathComponent("sessions.db").path
        openDatabase()
        createTables()
        loadAll()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Session CRUD

    func save(_ config: SessionConfig) throws {
        var config = config
        config.updatedAt = Date()

        let sql = """
            INSERT OR REPLACE INTO sessions
            (id, name, host, port, username, auth_method, protocol_type,
             private_key_path, auth_profile_id, group_id,
             keepalive_interval, login_script, terminal_type, notes, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bindUUID(stmt!, 1, config.id)
        sqlite3_bind_text(stmt!, 2, config.name, -1, TRANSIENT)
        sqlite3_bind_text(stmt!, 3, config.host, -1, TRANSIENT)
        sqlite3_bind_int(stmt!, 4, Int32(config.port))
        sqlite3_bind_text(stmt!, 5, config.username, -1, TRANSIENT)
        sqlite3_bind_text(stmt!, 6, config.authMethod.rawValue, -1, TRANSIENT)
        sqlite3_bind_text(stmt!, 7, config.protocolType.rawValue, -1, TRANSIENT)
        if let keyPath = config.privateKeyPath { sqlite3_bind_text(stmt!, 8, keyPath, -1, TRANSIENT) } else { sqlite3_bind_null(stmt!, 8) }
        bindOptionalUUID(stmt!, 9, config.authProfileID)
        bindOptionalUUID(stmt!, 10, config.groupID)
        sqlite3_bind_int(stmt!, 11, Int32(config.keepAliveInterval))
        if let script = config.loginScript { sqlite3_bind_text(stmt!, 12, script, -1, TRANSIENT) } else { sqlite3_bind_null(stmt!, 12) }
        sqlite3_bind_text(stmt!, 13, config.terminalType, -1, TRANSIENT)
        if let notes = config.notes { sqlite3_bind_text(stmt!, 14, notes, -1, TRANSIENT) } else { sqlite3_bind_null(stmt!, 14) }
        sqlite3_bind_double(stmt!, 15, config.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt!, 16, config.updatedAt.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw RepositoryError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }

        // Update in-memory
        if let idx = sessions.firstIndex(where: { $0.id == config.id }) {
            sessions[idx] = config
        } else {
            sessions.append(config)
        }
    }

    func delete(id: UUID) throws {
        let sql = "DELETE FROM sessions WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt!, 1, id)
        sqlite3_step(stmt)
        sessions.removeAll { $0.id == id }
    }

    func move(id: UUID, toGroup groupID: UUID?) throws {
        let sql = "UPDATE sessions SET group_id = ?, updated_at = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bindOptionalUUID(stmt!, 1, groupID)
        sqlite3_bind_double(stmt!, 2, Date().timeIntervalSince1970)
        bindUUID(stmt!, 3, id)
        sqlite3_step(stmt)

        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].groupID = groupID
        }
    }

    // MARK: - Import/Export

    func importSessions(from url: URL) throws -> [SessionConfig] {
        let data = try Data(contentsOf: url)
        let configs: [SessionConfig]
        if url.pathExtension == "csv" {
            configs = try importCSV(data)
        } else {
            configs = try JSONDecoder().decode([SessionConfig].self, from: data)
        }
        for config in configs {
            try? save(config)
        }
        return configs
    }

    func exportSessions(ids: [UUID], to url: URL) throws {
        let exportData = sessions.filter { ids.contains($0.id) }
        let data = try JSONEncoder().encode(exportData)
        try data.write(to: url)
    }

    // MARK: - Quick Commands

    func loadQuickCommands() -> [QuickCommand] {
        var cmds: [QuickCommand] = []
        let sql = "SELECT * FROM quick_commands ORDER BY sort_order, name"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idStr = sqlite3_column_text(stmt, 0),
                  let name = sqlite3_column_text(stmt, 1),
                  let command = sqlite3_column_text(stmt, 2) else { continue }
            cmds.append(QuickCommand(
                id: UUID(uuidString: String(cString: idStr)) ?? UUID(),
                name: String(cString: name),
                command: String(cString: command),
                category: stmt?[3].map { String(cString: $0) },
                sortOrder: Int(sqlite3_column_int(stmt, 4))
            ))
        }
        return cmds
    }

    func saveQuickCommand(_ cmd: QuickCommand) throws {
        let sql = """
            INSERT OR REPLACE INTO quick_commands (id, name, command, category, sort_order)
            VALUES (?, ?, ?, ?, ?)
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt!, 1, cmd.id)
        sqlite3_bind_text(stmt!, 2, cmd.name, -1, TRANSIENT)
        sqlite3_bind_text(stmt!, 3, cmd.command, -1, TRANSIENT)
        if let cat = cmd.category { sqlite3_bind_text(stmt!, 4, cat, -1, TRANSIENT) } else { sqlite3_bind_null(stmt!, 4) }
        sqlite3_bind_int(stmt!, 5, Int32(cmd.sortOrder))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw RepositoryError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
    }

    func deleteQuickCommand(id: UUID) throws {
        let sql = "DELETE FROM quick_commands WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RepositoryError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bindUUID(stmt!, 1, id)
        sqlite3_step(stmt)
    }

    // MARK: - Private

    private func openDatabase() {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            fatalError("Failed to open database at \(dbPath)")
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
    }

    private func createTables() {
        let sql = """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY, name TEXT, host TEXT NOT NULL,
                port INTEGER DEFAULT 22, username TEXT NOT NULL,
                auth_method TEXT DEFAULT 'key',
                protocol_type TEXT DEFAULT 'SSH',
                private_key_path TEXT, auth_profile_id TEXT, group_id TEXT,
                keepalive_interval INTEGER DEFAULT 60, login_script TEXT,
                terminal_type TEXT DEFAULT 'xterm-256color', notes TEXT,
                created_at REAL, updated_at REAL
            );
            CREATE TABLE IF NOT EXISTS session_groups (
                id TEXT PRIMARY KEY, name TEXT NOT NULL,
                parent_id TEXT, sort_order INTEGER DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS quick_commands (
                id TEXT PRIMARY KEY, name TEXT NOT NULL,
                command TEXT NOT NULL, category TEXT,
                sort_order INTEGER DEFAULT 0
            );
            """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func loadAll() {
        var stmt: OpaquePointer?
        let sql = "SELECT * FROM sessions ORDER BY name"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        var loaded: [SessionConfig] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let config = mapSession(stmt!) { loaded.append(config) }
        }
        sessions = loaded
    }

    private func mapSession(_ stmt: OpaquePointer) -> SessionConfig? {
        guard let idStr = sqlite3_column_text(stmt, 0),
              let host = sqlite3_column_text(stmt, 2),
              let user = sqlite3_column_text(stmt, 4) else { return nil }

        return SessionConfig(
            id: UUID(uuidString: String(cString: idStr)) ?? UUID(),
            name: String(cString: coalesce(stmt, 1, "")),
            host: String(cString: host),
            port: UInt16(sqlite3_column_int(stmt, 3)),
            protocolType: ProtocolType(rawValue: String(cString: coalesce(stmt, 6, "SSH"))) ?? .ssh,
            username: String(cString: user),
            authMethod: AuthMethod(rawValue: String(cString: coalesce(stmt, 5, "key"))) ?? .key,
            authProfileID: stmt[8].flatMap { UUID(uuidString: String(cString: $0)) },
            privateKeyPath: stmt[7].map { String(cString: $0) },
            groupID: stmt[9].flatMap { UUID(uuidString: String(cString: $0)) },
            keepAliveInterval: Int(sqlite3_column_int(stmt, 10)),
            loginScript: stmt[11].map { String(cString: $0) },
            terminalType: String(cString: coalesce(stmt, 12, "xterm-256color")),
            notes: stmt[13].map { String(cString: $0) },
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 15))
        )
    }

    // MARK: - Helpers
    private func bindUUID(_ stmt: OpaquePointer, _ idx: Int32, _ uuid: UUID) {
        sqlite3_bind_text(stmt, idx, uuid.uuidString, -1, TRANSIENT)
    }

    private func bindOptionalUUID(_ stmt: OpaquePointer, _ idx: Int32, _ uuid: UUID?) {
        if let uuid = uuid { bindUUID(stmt, idx, uuid) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    private func coalesce(_ stmt: OpaquePointer, _ idx: Int32, _ fallback: String) -> UnsafePointer<CChar> {
        if let ptr = sqlite3_column_text(stmt, idx) {
            return UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
        }
        return UnsafeRawPointer((fallback as NSString).utf8String!).assumingMemoryBound(to: CChar.self)
    }

    // CSV import helper
    private func importCSV(_ data: Data) throws -> [SessionConfig] {
        guard let csv = String(data: data, encoding: .utf8) else { throw RepositoryError.invalidFormat }
        var configs: [SessionConfig] = []
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let header = lines.first else { return [] }
        let columns = header.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for line in lines.dropFirst() {
            let values = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard values.count >= columns.count else { continue }
            var dict: [String: String] = [:]
            for (i, col) in columns.enumerated() { dict[col] = values[i] }

            configs.append(SessionConfig(
                name: dict["name"] ?? "",
                host: dict["host"] ?? "",
                port: UInt16(dict["port"] ?? "22") ?? 22,
                username: dict["username"] ?? "",
                authMethod: AuthMethod(rawValue: dict["authMethod"] ?? "key") ?? .key
            ))
        }
        return configs
    }
}

enum RepositoryError: Error {
    case sqliteError(String)
    case invalidFormat
    case notFound
}

extension OpaquePointer {
    subscript(_ idx: Int32) -> UnsafePointer<CChar>? {
        guard let ptr = sqlite3_column_text(self, idx) else { return nil }
        return UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
    }
}
