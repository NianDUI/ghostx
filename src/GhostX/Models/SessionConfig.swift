import Foundation

/// SSH session configuration - persisted to SQLite
struct SessionConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: UInt16 = 22
    var username: String
    var authMethod: AuthMethod = .key
    var privateKeyPath: String?
    var groupID: UUID?
    var keepAliveInterval: Int = 60
    var proxy: ProxyConfig?
    var loginScript: String?
    var terminalType: String = "xterm-256color"
    var tags: [String] = []
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastConnectedAt: Date?
    var connectCount: Int = 0

    // MARK: - Computed
    var displayTitle: String { name.isEmpty ? "\(username)@\(host)" : name }
    var connectionString: String { "\(username)@\(host):\(port)" }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, authMethod
        case privateKeyPath, groupID, keepAliveInterval, loginScript
        case terminalType, notes, createdAt, updatedAt
    }
}

enum AuthMethod: String, Codable, CaseIterable {
    case password
    case key
    case agent
}

/// Session folder/group for tree organization
struct SessionGroup: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var parentID: UUID?
    var sortOrder: Int = 0
}
