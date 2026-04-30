import SwiftUI

/// Batch edit multiple sessions' common properties
struct BulkEditView: View {
    @ObservedObject var repo: SessionRepository
    let selectedIDs: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    @State private var setKeepAlive: Bool = false
    @State private var keepAliveValue: String = "60"
    @State private var setProxy: Bool = false
    @State private var proxyEnabled: Bool = true
    @State private var proxyType: ProxyConfig.ProxyType = .socks5
    @State private var proxyHost: String = "127.0.0.1"
    @State private var proxyPort: String = "1080"
    @State private var setKey: Bool = false
    @State private var keyPath: String = ""
    @State private var setTerminal: Bool = false
    @State private var terminalType: String = "xterm-256color"

    private var selectedSessions: [SessionConfig] {
        repo.sessions.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bulk Edit Sessions")
                .font(.title2)
            Text("Editing \(selectedIDs.count) session(s)")
                .font(.caption).foregroundColor(.secondary)

            Form {
                // Keep Alive
                Section("Keep Alive (seconds)") {
                    Toggle("Set keep alive", isOn: $setKeepAlive)
                    if setKeepAlive {
                        TextField("Interval (s)", text: $keepAliveValue, prompt: Text("60"))
                    }
                }

                // Proxy
                Section("Proxy") {
                    Toggle("Set proxy", isOn: $setProxy)
                    if setProxy {
                        Toggle("Enabled", isOn: $proxyEnabled)
                        Picker("Type:", selection: $proxyType) {
                            Text("SOCKS5").tag(ProxyConfig.ProxyType.socks5)
                            Text("SOCKS4").tag(ProxyConfig.ProxyType.socks4)
                            Text("HTTP").tag(ProxyConfig.ProxyType.http)
                        }
                        HStack {
                            TextField("Host", text: $proxyHost)
                            Text(":").foregroundColor(.secondary)
                            TextField("Port", text: $proxyPort).frame(width: 60)
                        }
                    }
                }

                // SSH Key
                Section("SSH Key") {
                    Toggle("Set private key path", isOn: $setKey)
                    if setKey {
                        HStack {
                            TextField("Key path", text: $keyPath)
                            Button("Browse...") {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.data]
                                if panel.runModal() == .OK { keyPath = panel.url?.path ?? keyPath }
                            }
                        }
                    }
                }

                // Terminal
                Section("Terminal") {
                    Toggle("Set terminal type", isOn: $setTerminal)
                    if setTerminal {
                        TextField("TERM", text: $terminalType)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Apply to \(selectedIDs.count) Sessions") { applyChanges() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 450, height: 500)
    }

    private func applyChanges() {
        for var session in selectedSessions {
            if setKeepAlive { session.keepAliveInterval = Int(keepAliveValue) ?? 60 }
            if setProxy {
                session.proxy = ProxyConfig(
                    enabled: proxyEnabled, type: proxyType,
                    host: proxyHost, port: UInt16(proxyPort) ?? 1080
                )
            }
            if setKey { session.privateKeyPath = keyPath.isEmpty ? nil : keyPath }
            if setTerminal { session.terminalType = terminalType }
            try? repo.save(session)
        }
        dismiss()
    }
}
