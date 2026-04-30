import SwiftUI

/// Sheet for creating a new SSH session
struct NewSessionSheet: View {
    @ObservedObject var repo: SessionRepository
    @ObservedObject var tabManager: TabManager
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var protocolType: ProtocolType = .ssh
    @State private var username: String = NSUserName()
    @State private var authMethod: AuthMethod = .key
    @State private var privateKeyPath: String = "~/.ssh/id_ed25519"
    @State private var loginScript: String = ""
    @State private var proxyEnabled: Bool = false
    @State private var proxyType: ProxyConfig.ProxyType = .socks5
    @State private var proxyHost: String = "127.0.0.1"
    @State private var proxyPort: String = "1080"
    @State private var connectOnSave: Bool = true

    var body: some View {
        VStack(spacing: 16) {
            Text("New SSH Session")
                .font(.title2)
                .padding(.top, 20)

            Form {
                TextField("Session Name:", text: $name, prompt: Text("Optional label"))

                HStack {
                    Picker("Protocol:", selection: $protocolType) {
                        Text("SSH").tag(ProtocolType.ssh)
                        Text("TELNET").tag(ProtocolType.telnet)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: protocolType) { _, newProto in
                        port = newProto == .ssh ? "22" : "23"
                    }
                }
                HStack {
                    TextField("Host:", text: $host, prompt: Text("192.168.1.1"))
                    Text(":")
                    TextField(port, text: $port)
                        .frame(width: 60)
                }

                TextField("Username:", text: $username)

                Picker("Auth:", selection: $authMethod) {
                    Text("Key").tag(AuthMethod.key)
                    Text("Password").tag(AuthMethod.password)
                    Text("Agent").tag(AuthMethod.agent)
                }
                .pickerStyle(.segmented)

                if authMethod == .key {
                    HStack {
                        TextField("Private Key:", text: $privateKeyPath)
                        Button(action: browseKey) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Browse for private key")
                        Button(action: generateKey) {
                            Image(systemName: "key")
                        }
                        .buttonStyle(.borderless)
                        .help("Generate new key pair")
                    }
                }

                TextField("Login Script:", text: $loginScript, prompt: Text("Commands to run after login"))

                // Proxy settings
                DisclosureGroup("Proxy Settings") {
                    Toggle("Enable Proxy", isOn: $proxyEnabled)
                    if proxyEnabled {
                        Picker("Type:", selection: $proxyType) {
                            Text("SOCKS5").tag(ProxyConfig.ProxyType.socks5)
                            Text("SOCKS4").tag(ProxyConfig.ProxyType.socks4)
                            Text("HTTP").tag(ProxyConfig.ProxyType.http)
                        }
                        HStack {
                            TextField("Proxy Host:", text: $proxyHost)
                            Text(":").foregroundColor(.secondary)
                            TextField("Port:", text: $proxyPort)
                                .frame(width: 60)
                        }
                    }
                }

                Toggle("Connect after saving", isOn: $connectOnSave)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    saveSession()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(host.isEmpty || username.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 400, height: 450)
    }

    private func browseKey() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
        panel.allowsMultipleSelection = false
        panel.title = "Select Private Key"
        if panel.runModal() == .OK, let url = panel.url {
            privateKeyPath = url.path
        }
    }

    private func generateKey() {
        let panel = NSSavePanel()
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")
        panel.nameFieldStringValue = "id_ed25519"
        panel.title = "Save New Key"
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            task.arguments = ["-t", "ed25519", "-f", path, "-N", "", "-q"]
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                privateKeyPath = path
            }
        }
    }

    private func saveSession() {
        var config = SessionConfig(
            name: name,
            host: host.trimmingCharacters(in: .whitespaces),
            port: UInt16(port) ?? (protocolType == .ssh ? 22 : 23),
            protocolType: protocolType,
            username: username.trimmingCharacters(in: .whitespaces),
            authMethod: authMethod,
            privateKeyPath: authMethod == .key ? privateKeyPath : nil,
            proxy: proxyEnabled ? ProxyConfig(
                enabled: true, type: proxyType,
                host: proxyHost, port: UInt16(proxyPort) ?? 1080
            ) : nil,
            loginScript: loginScript.isEmpty ? nil : loginScript
        )

        if connectOnSave {
            tabManager.openTab(for: config)
        }

        isPresented = false
    }
}
