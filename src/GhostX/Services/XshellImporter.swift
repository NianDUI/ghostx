import Foundation

/// Imports Xshell .xsh session files with directory hierarchy preservation
enum XshellImporter {
    struct ParsedSession {
        var name: String
        let host: String
        let port: UInt16
        let protocolType: ProtocolType
        let username: String
        var groupPath: [String]
        let keepAliveInterval: Int
        let terminalType: String
        let rows: Int
        let cols: Int
        let privateKeyPath: String?
    }

    /// Walk the Xshell Sessions directory and parse all .xsh files
    static func scanDirectory(_ rootPath: String) -> [ParsedSession] {
        var sessions: [ParsedSession] = []
        let baseURL = URL(fileURLWithPath: rootPath)

        guard let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "xsh" else { continue }

            // Calculate group path from directory structure
            let relative = fileURL.deletingLastPathComponent().path
                .replacingOccurrences(of: baseURL.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let groups = relative.isEmpty ? [] : relative.components(separatedBy: "/").filter { !$0.isEmpty }

            // Parse the .xsh file
            guard let parsed = parseFile(fileURL.path) else { continue }
            let session = ParsedSession(
                name: parsed.name.isEmpty ? fileURL.deletingLastPathComponent().lastPathComponent : parsed.name,
                host: parsed.host, port: parsed.port, protocolType: parsed.protocolType,
                username: parsed.username, groupPath: groups,
                keepAliveInterval: parsed.keepAliveInterval, terminalType: parsed.terminalType,
                rows: parsed.rows, cols: parsed.cols, privateKeyPath: parsed.privateKeyPath
            )
            sessions.append(session)
        }
        return sessions
    }

    /// Parse a single .xsh file (UTF-16LE INI format)
    static func parseFile(_ path: String) -> ParsedSession? {
        guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }

        // Strip BOM if present
        let data: Data
        if rawData.count >= 2 && rawData[0] == 0xFF && rawData[1] == 0xFE {
            data = rawData.subdata(in: 2..<rawData.count)
        } else {
            data = rawData
        }

        // Convert UTF-16LE to string
        guard let content = String(data: data, encoding: .utf16LittleEndian) else { return nil }

        // Parse INI sections
        var currentSection = ""
        var kv: [String: [String: String]] = [:]

        for line in content.components(separatedBy: "\r\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).uppercased()
                if kv[currentSection] == nil { kv[currentSection] = [:] }
                continue
            }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
            let value = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
            if !currentSection.isEmpty {
                kv[currentSection]?[key] = value
            }
        }

        // Extract fields
        let conn = kv["CONNECTION"] ?? [:]
        let auth = kv["CONNECTION:AUTHENTICATION"] ?? [:]
        let term = kv["TERMINAL"] ?? [:]
        let ka = kv["CONNECTION:KEEPALIVE"] ?? [:]

        let host = conn["HOST"] ?? ""
        guard !host.isEmpty else { return nil }

        let proto = (conn["PROTOCOL"] ?? "SSH").uppercased()
        let protocolType: ProtocolType = proto == "TELNET" ? .telnet : .ssh

        return ParsedSession(
            name: conn["DESCRIPTION"] ?? "",
            host: host,
            port: UInt16(conn["PORT"] ?? (protocolType == .ssh ? "22" : "23")) ?? (protocolType == .ssh ? 22 : 23),
            protocolType: protocolType,
            username: auth["USERNAME"] ?? "root",
            groupPath: [],
            keepAliveInterval: Int(ka["KEEPALIVEINTERVAL"] ?? "60") ?? 60,
            terminalType: term["TYPE"] ?? "xterm",
            rows: Int(term["ROWS"] ?? "24") ?? 24,
            cols: Int(term["COLS"] ?? "80") ?? 80,
            privateKeyPath: (auth["USERKEY"]?.isEmpty == false) ? auth["USERKEY"] : nil
        )
    }

    /// Convert parsed sessions to GhostX SessionConfig, creating groups as needed
    static func importToRepository(
        _ sessions: [ParsedSession],
        repo: SessionRepository
    ) -> (imported: Int, groups: Int) {
        var groupMap: [String: UUID] = [:]  // group path string → group UUID
        var imported = 0

        for parsed in sessions {
            // Create parent group chain
            var parentID: UUID?
            var currentPath = ""
            for segment in parsed.groupPath {
                currentPath += (currentPath.isEmpty ? "" : "/") + segment
                if let existing = groupMap[currentPath] {
                    parentID = existing
                } else {
                    let group = SessionGroup(name: segment, parentID: parentID)
                    groupMap[currentPath] = group.id
                    parentID = group.id
                    // Note: SessionRepository doesn't persist groups currently,
                    // but the groupID is stored on each session
                }
            }

            let config = SessionConfig(
                name: parsed.name.isEmpty ? "\(parsed.username)@\(parsed.host)" : parsed.name,
                host: parsed.host,
                port: parsed.port,
                protocolType: parsed.protocolType,
                username: parsed.username,
                authMethod: parsed.privateKeyPath != nil ? .key : .password,
                privateKeyPath: parsed.privateKeyPath,
                groupID: parentID,
                keepAliveInterval: parsed.keepAliveInterval,
                terminalType: parsed.terminalType
            )
            try? repo.save(config)
            imported += 1
        }
        return (imported, groupMap.count)
    }
}
