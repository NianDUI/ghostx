import Foundation

/// SSH tunnel / port forwarding configuration
struct TunnelConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var type: TunnelType = .local
    var localHost: String = "127.0.0.1"
    var localPort: UInt16 = 8080
    var remoteHost: String = "127.0.0.1"
    var remotePort: UInt16 = 80
    var enabled: Bool = true
    var createdAt: Date = Date()
    var status: TunnelStatus = .stopped

    enum TunnelType: String, Codable, CaseIterable {
        case local = "Local"   // -L: local:port → remote:port
        case remote = "Remote" // -R: remote:port → local:port
        case dynamic = "Dynamic" // -D: SOCKS proxy on local:port

        var flag: String {
            switch self {
            case .local: return "-L"
            case .remote: return "-R"
            case .dynamic: return "-D"
            }
        }

        var description: String {
            switch self {
            case .local: return "Local port forwarded to remote"
            case .remote: return "Remote port forwarded to local"
            case .dynamic: return "SOCKS5 proxy on local port"
            }
        }
    }

    enum TunnelStatus: String, Codable {
        case active, stopped, error
    }

    /// Build the ssh command flag
    var sshFlag: String {
        switch type {
        case .local:
            return "\(localHost):\(localPort):\(remoteHost):\(remotePort)"
        case .remote:
            return "\(remoteHost):\(remotePort):\(localHost):\(localPort)"
        case .dynamic:
            return "\(localPort)"
        }
    }
}

/// Proxy configuration for outbound SSH connections
struct ProxyConfig: Codable, Hashable {
    var enabled: Bool = false
    var type: ProxyType = .socks5
    var host: String = "127.0.0.1"
    var port: UInt16 = 1080
    var username: String?
    var password: String?

    enum ProxyType: String, Codable, CaseIterable {
        case socks4 = "SOCKS4"
        case socks5 = "SOCKS5"
        case http = "HTTP"

        var sshOption: String {
            switch self {
            case .socks4: return "ProxyCommand=nc -X 4 -x"
            case .socks5: return "ProxyCommand=nc -X 5 -x"
            case .http: return "ProxyCommand=nc -X connect -x"
            }
        }
    }

    var sshProxyCommand: String? {
        guard enabled else { return nil }
        var cmd = "\(type.sshOption) \(host):\(port) %h %p"
        if let user = username {
            cmd = "ProxyCommand=nc -X \(type == .socks5 ? "5" : type == .socks4 ? "4" : "connect") -x \(host):\(port)\(user.isEmpty ? "" : " -P \(user)") %h %p"
        }
        return cmd
    }
}
