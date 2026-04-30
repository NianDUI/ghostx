import SwiftUI

/// Port forwarding / SSH tunnel management view
struct TunnelManagerView: View {
    let sessionID: UUID
    @State private var tunnels: [TunnelConfig] = []
    @State private var showAddSheet = false
    @State private var editingTunnel: TunnelConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Port Forwarding & Tunnels")
                .font(.title2)
                .padding(.top)

            if tunnels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No tunnels configured")
                        .foregroundColor(.secondary)
                    Text("Add a tunnel to forward ports between local and remote hosts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(tunnels) { tunnel in
                        TunnelRow(tunnel: tunnel, onToggle: { toggleTunnel(tunnel) },
                                  onEdit: { editingTunnel = tunnel },
                                  onDelete: { deleteTunnel(tunnel) })
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Quick presets
            HStack {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                    Text(L10n.addTunnel)
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Menu("Presets") {
                    Button("SOCKS5 Proxy :1080") { addPreset(.dynamic, localPort: 1080, name: "SOCKS5 Proxy") }
                    Button("Web :8080 → :80") { addPreset(.local, localPort: 8080, remotePort: 80, name: "Web Forward") }
                    Button("MySQL :3306 → :3306") { addPreset(.local, localPort: 3306, remotePort: 3306, name: "MySQL Tunnel") }
                    Button("Remote :9090 → :3000") { addPreset(.remote, localPort: 3000, remotePort: 9090, name: "Remote Dev") }
                }
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 500, height: 400)
        .sheet(isPresented: $showAddSheet) {
            TunnelEditSheet(tunnels: $tunnels, isPresented: $showAddSheet)
        }
        .sheet(item: $editingTunnel) { tunnel in
            TunnelEditSheet(tunnels: $tunnels, editing: tunnel, isPresented: .constant(true))
        }
        .onAppear { loadTunnels() }
    }

    private func toggleTunnel(_ tunnel: TunnelConfig) {
        if let idx = tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            tunnels[idx].enabled.toggle()
            saveTunnels()
        }
    }

    private func deleteTunnel(_ tunnel: TunnelConfig) {
        tunnels.removeAll { $0.id == tunnel.id }
        saveTunnels()
    }

    private func addPreset(_ type: TunnelConfig.TunnelType, localPort: UInt16, remotePort: UInt16 = 80, name: String) {
        let tunnel = TunnelConfig(
            name: name, type: type,
            localPort: localPort, remotePort: remotePort
        )
        tunnels.append(tunnel)
        saveTunnels()
    }

    private func loadTunnels() {
        let key = "GhostX.tunnels.\(sessionID.uuidString)"
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([TunnelConfig].self, from: data) {
            tunnels = saved
        }
    }

    private func saveTunnels() {
        let key = "GhostX.tunnels.\(sessionID.uuidString)"
        if let data = try? JSONEncoder().encode(tunnels) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Single tunnel row in the list
struct TunnelRow: View {
    let tunnel: TunnelConfig
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: .constant(tunnel.enabled))
                .onTapGesture { onToggle() }
                .toggleStyle(.checkbox)

            Image(systemName: tunnel.type == .dynamic ? "network" :
                    tunnel.type == .local ? "arrow.right" : "arrow.left")
                .foregroundColor(tunnel.enabled ? .green : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(tunnel.name.isEmpty ? "\(tunnel.type.rawValue) Tunnel" : tunnel.name)
                    .font(.body)
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        switch tunnel.type {
        case .local:
            return "localhost:\(tunnel.localPort) → \(tunnel.remoteHost):\(tunnel.remotePort)"
        case .remote:
            return "\(tunnel.remoteHost):\(tunnel.remotePort) → localhost:\(tunnel.localPort)"
        case .dynamic:
            return "SOCKS5 localhost:\(tunnel.localPort)"
        }
    }
}

/// Add/edit a tunnel
struct TunnelEditSheet: View {
    @Binding var tunnels: [TunnelConfig]
    var editing: TunnelConfig?
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var type: TunnelConfig.TunnelType = .local
    @State private var localHost = "127.0.0.1"
    @State private var localPort = "8080"
    @State private var remoteHost = "127.0.0.1"
    @State private var remotePort = "80"

    var body: some View {
        VStack(spacing: 12) {
            Text(editing != nil ? "Edit Tunnel" : "New Tunnel")
                .font(.title2)

            TextField("Name", text: $name, prompt: Text("Optional name"))

            Picker("Type:", selection: $type) {
                Text("Local (-L)").tag(TunnelConfig.TunnelType.local)
                Text("Remote (-R)").tag(TunnelConfig.TunnelType.remote)
                Text("Dynamic SOCKS5 (-D)").tag(TunnelConfig.TunnelType.dynamic)
            }
            .pickerStyle(.segmented)

            if type != .dynamic {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Source").font(.caption).foregroundColor(.secondary)
                        HStack {
                            TextField("host", text: $localHost).frame(width: 100)
                            Text(":").foregroundColor(.secondary)
                            TextField("port", text: $localPort).frame(width: 60)
                        }
                    }
                    Spacer()
                    Image(systemName: "arrow.right").foregroundColor(.secondary)
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Destination").font(.caption).foregroundColor(.secondary)
                        HStack {
                            TextField("host", text: $remoteHost).frame(width: 100)
                            Text(":").foregroundColor(.secondary)
                            TextField("port", text: $remotePort).frame(width: 60)
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
            } else {
                TextField("SOCKS Port:", text: $localPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button(editing != nil ? "Update" : "Add") {
                    var tunnel = editing ?? TunnelConfig()
                    tunnel.name = name
                    tunnel.type = type
                    tunnel.localHost = localHost
                    tunnel.localPort = UInt16(localPort) ?? 8080
                    tunnel.remoteHost = remoteHost
                    tunnel.remotePort = UInt16(remotePort) ?? 80
                    if let idx = tunnels.firstIndex(where: { $0.id == tunnel.id }) {
                        tunnels[idx] = tunnel
                    } else {
                        tunnels.append(tunnel)
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 420, height: type == .dynamic ? 250 : 310)
        .onAppear {
            if let t = editing {
                name = t.name; type = t.type
                localHost = t.localHost; localPort = "\(t.localPort)"
                remoteHost = t.remoteHost; remotePort = "\(t.remotePort)"
            }
        }
    }
}
