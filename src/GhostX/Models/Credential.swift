import Foundation

struct Credential {
    let host: String
    let username: String
    let secret: Secret

    enum Secret {
        case password(String)
        case privateKey(Data)
    }
}

/// Quick command - saved command that can be sent to sessions
struct QuickCommand: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var command: String
    var category: String?
    var sortOrder: Int = 0
}

/// Log entry for session logging
struct SessionLogEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var sessionID: UUID
    var timestamp: Date
    var direction: Direction
    var data: Data

    enum Direction: String, Codable {
        case input
        case output
    }
}

/// Trigger condition + action
struct Trigger: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var pattern: String       // regex pattern
    var action: TriggerAction
    var enabled: Bool = true

    enum TriggerAction: Codable, Hashable {
        case highlight
        case notify(String)
        case runCommand(String)
        case disconnect
    }
}
