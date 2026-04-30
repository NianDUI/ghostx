import SwiftUI

@main
struct GhostXApp: App {
    @StateObject private var sessionRepo = SessionRepository()

    var body: some Scene {
        Window("GhostX", id: "main") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Session...") {
                    // Triggered via NotificationCenter to avoid tight coupling
                    NotificationCenter.default.post(name: .init("GhostXNewSession"), object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("Session") {
                Button("Quick Connect...") {
                    NotificationCenter.default.post(name: .init("GhostXQuickConnect"), object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command])

                Divider()

                Button("Broadcast to All...") {
                    NotificationCenter.default.post(name: .init("GhostXBroadcastToggle"), object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// App settings
struct SettingsView: View {
    @AppStorage("defaultTerminalType") private var terminalType = "xterm-256color"
    @AppStorage("defaultKeepAlive") private var keepAlive = 60
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("GhostX.wordSeparators") private var wordSeparators = " \t\n\"'`@$><=;|&{}()[]#,"
    @AppStorage("GhostX.language") private var language = "zh"

    var body: some View {
        TabView {
            Form {
                Picker("Language / 语言:", selection: $language) {
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                Text("Restart app to apply language change")
                    .font(.caption).foregroundColor(.secondary)
                TextField("Terminal Type:", text: $terminalType)
                TextField("Keep Alive (s):", value: $keepAlive, format: .number)
            }
            .tabItem { Text("General") }
            .padding()

            Form {
                Slider(value: $fontSize, in: 8...36, step: 1) {
                    Text("Font Size: \(Int(fontSize))")
                }
                TextField("Word separators:", text: $wordSeparators)
                    .onChange(of: wordSeparators) { _, v in
                        UserDefaults.standard.set(v, forKey: "GhostX.wordSeparators")
                    }
                Text("Characters that delimit words for double-click selection")
                    .font(.caption).foregroundColor(.secondary)
            }
            .tabItem { Text("Appearance") }
            .padding()

            AuthProfileSettingsView()
                .tabItem { Text("Auth Profiles") }
                .padding()

            KeyManagementView()
                .tabItem { Text("SSH Keys") }
                .padding()
        }
        .frame(width: 500, height: 350)
    }
}

/// Auth profile management in settings
struct AuthProfileSettingsView: View {
    @StateObject private var manager = AuthProfileManager()
    @State private var showEditor = false
    @State private var editingProfile: AuthProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Authentication Profiles").font(.title3)
            Text("Reusable credential configs applied to multiple sessions").font(.caption).foregroundColor(.secondary)

            List(manager.profiles) { profile in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name).font(.body)
                        Text("\(profile.username) — \(profile.authMethod == .key ? "Key" : "Password")")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Edit") { editingProfile = profile }
                        .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
            .frame(height: 120)

            HStack {
                Button("New Profile...") {
                    editingProfile = AuthProfile(name: "")
                    showEditor = true
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
        .sheet(item: $editingProfile) { profile in
            AuthProfileEditor(manager: manager, profile: profile)
        }
    }
}

struct AuthProfileEditor: View {
    @ObservedObject var manager: AuthProfileManager
    @State var profile: AuthProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text(profile.name.isEmpty ? "New Auth Profile" : "Edit Auth Profile").font(.title2)
            Form {
                TextField("Name", text: $profile.name)
                TextField("Username", text: $profile.username)
                Picker("Auth Method", selection: $profile.authMethod) {
                    Text("Key").tag(AuthMethod.key)
                    Text("Password").tag(AuthMethod.password)
                    Text("Agent").tag(AuthMethod.agent)
                }
                if profile.authMethod == .key {
                    HStack {
                        TextField("Private Key", text: Binding(
                            get: { profile.privateKeyPath ?? "" },
                            set: { profile.privateKeyPath = $0.isEmpty ? nil : $0 }
                        ))
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.data]
                            if panel.runModal() == .OK { profile.privateKeyPath = panel.url?.path }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { manager.save(profile); dismiss() }
                    .buttonStyle(.borderedProminent).disabled(profile.name.isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 320)
    }
}



/// SSH key management in settings
struct KeyManagementView: View {
    @State private var keys: [SSHKeyInfo] = []
    @State private var showGenerate = false

    struct SSHKeyInfo: Identifiable {
        let id = UUID()
        let path: String
        let type: String
        let size: String
        let fingerprint: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SSH Keys").font(.title3)

            List(keys) { key in
                HStack {
                    Image(systemName: "key")
                        .foregroundColor(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.path).font(.caption)
                        Text("\(key.type) \(key.size) — \(key.fingerprint)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .frame(height: 120)

            HStack {
                Button("Generate New Key...") { showGenerate = true }
                    .sheet(isPresented: $showGenerate) { KeyGenerateView { reloadKeys() } }
                Button("Import...") { importKey() }
                    .buttonStyle(.borderless)
                Button("Refresh") { reloadKeys() }
                    .buttonStyle(.borderless)
                Spacer()
            }
        }
        .onAppear { reloadKeys() }
    }

    private func reloadKeys() {
        let sshDir = NSHomeDirectory() + "/.ssh"
        keys = []
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: sshDir) else { return }
        for entry in contents where !entry.hasSuffix(".pub") && !entry.hasPrefix("known_hosts") && !entry.hasPrefix("authorized") {
            let path = sshDir + "/" + entry
            // Read public key to get type and comment
            let pubPath = path + ".pub"
            var type = "private", size = "", fp = ""
            if let pub = try? String(contentsOfFile: pubPath, encoding: .utf8) {
                let parts = pub.components(separatedBy: " ")
                if parts.count >= 2 {
                    type = parts[0]
                    if parts.count >= 3 { fp = parts[2].suffix(16) + "..." }
                }
            }
            // Get file size for rough key size
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let fileSize = attrs[.size] as? Int {
                size = formatBytes(fileSize)
            }
            keys.append(SSHKeyInfo(path: path, type: type, size: size, fingerprint: String(fp)))
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }

    private func importKey() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let dest = NSHomeDirectory() + "/.ssh/" + url.lastPathComponent
        try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: dest))
        // Set correct permissions
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest)
        reloadKeys()
    }
}

/// Key generation sheet
struct KeyGenerateView: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keyType = "ed25519"
    @State private var comment = ""
    @State private var generating = false
    @State private var errorMsg: String?

    var body: some View {
        VStack(spacing: 12) {
            Text("Generate SSH Key")
                .font(.title2)

            Picker("Type:", selection: $keyType) {
                Text("ED25519 (recommended)").tag("ed25519")
                Text("RSA 4096").tag("rsa")
                Text("ECDSA").tag("ecdsa")
            }
            .pickerStyle(.radioGroup)

            TextField("Comment (email):", text: $comment)
                .textFieldStyle(.roundedBorder)

            if let error = errorMsg {
                Text(error).font(.caption).foregroundColor(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(generating ? "Generating..." : "Generate") {
                    generate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(generating)
            }
        }
        .padding()
        .frame(width: 350, height: 220)
    }

    private func generate() {
        generating = true
        let name = keyType == "rsa" ? "id_rsa" : "id_\(keyType)"
        let path = NSHomeDirectory() + "/.ssh/\(name)"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        var args = ["-t", keyType, "-f", path, "-N", "", "-q"]
        if keyType == "rsa" { args.insert(contentsOf: ["-b", "4096"], at: 1) }
        if !comment.isEmpty { args.append(contentsOf: ["-C", comment]) }
        task.arguments = args

        let errPipe = Pipe()
        task.standardError = errPipe
        task.terminationHandler = { proc in
            DispatchQueue.main.async {
                generating = false
                if proc.terminationStatus == 0 {
                    onDone()
                    dismiss()
                } else {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    errorMsg = String(data: data, encoding: .utf8) ?? "Generation failed"
                }
            }
        }
        try? task.run()
    }
}

