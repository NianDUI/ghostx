import SwiftUI

/// Main window content with session sidebar, terminal area, and optional bottom panel
struct ContentView: View {
    @StateObject private var sessionRepo = SessionRepository()
    @StateObject private var tabManager = TabManager()
    @StateObject private var splitManager = SplitManager()
    @State private var hasSetupSplit = false
    @State private var showComposePanel = false
    @State private var showSFTP = false
    @State private var showTriggers = false
    @State private var showThemes = false
    @State private var showTunnels = false
    @State private var sidebarCollapsed = false
    @State private var sidebarWidth: CGFloat = 260
    @State private var selectedGroupID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar: Session tree + quick connect (collapsible)
            if !sidebarCollapsed {
                VStack(spacing: 0) {
                    SessionSidebar(
                        repo: sessionRepo,
                        tabManager: tabManager,
                        selectedGroupID: $selectedGroupID
                    )
                }
                .frame(width: sidebarWidth)
                .frame(minHeight: 400)
                .background(Color(NSColor.windowBackgroundColor))
                Divider()
            }

            // Toggle sidebar button
            VStack {
                Button(action: { withAnimation { sidebarCollapsed.toggle() } }) {
                    Image(systemName: sidebarCollapsed ? "sidebar.right" : "sidebar.left")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 4)
                Spacer()
            }
            .frame(width: sidebarCollapsed ? 20 : 4)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            // Right: Terminal area with splits + optional bottom panel
            VSplitView {
                // Terminal with split support
                if tabManager.tabs.isEmpty {
                    VStack {
                        Image(systemName: "terminal")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No sessions open")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Double-click a session in the sidebar or use Quick Connect")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SplitTreeView(splitManager: splitManager, tabManager: tabManager, node: splitManager.root)
                }

                // Bottom: Compose panel (togglable)
                if showComposePanel {
                    ComposePanel(tabManager: tabManager, showPanel: $showComposePanel)
                        .frame(minHeight: 80, idealHeight: 120)
                        .frame(maxHeight: 200)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: { showComposePanel.toggle() }) {
                    Image(systemName: "rectangle.3.group")
                        .help("Toggle Compose Panel")
                }
                Button(action: { showSFTP = true }) {
                    Image(systemName: "folder")
                        .help("SFTP File Browser")
                }
                Button(action: { showTriggers = true }) {
                    Image(systemName: "bolt")
                        .help("Trigger Configuration")
                }
                Button(action: { showThemes = true }) {
                    Image(systemName: "paintpalette")
                        .help("Terminal Themes")
                }
                Button(action: { showTunnels = true }) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .help("Port Forwarding & Tunnels")
                }
            }
        }
        .onAppear {
            tabManager.splitManager = splitManager
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .sheet(isPresented: $showSFTP) {
            if let activeTab = tabManager.tabs.first(where: { $0.id == tabManager.activeTabID }) {
                SFTPPanel(config: activeTab.config, nativeClient: activeTab.client.nativeClient)
            }
        }
        .sheet(isPresented: $showTriggers) {
            TriggerConfigView()
        }
        .sheet(isPresented: $showThemes) {
            ThemePickerView()
        }
        .sheet(isPresented: $showTunnels) {
            if let activeTab = tabManager.tabs.first(where: { $0.id == tabManager.activeTabID }) {
                TunnelManagerView(sessionID: activeTab.sessionID)
            }
        }
    }
}

/// Left sidebar with session tree, quick connect, and import/export
struct SessionSidebar: View {
    @ObservedObject var repo: SessionRepository
    @ObservedObject var tabManager: TabManager
    @Binding var selectedGroupID: UUID?
    @State private var quickHost: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Quick connect bar
            QuickConnectBar(repo: repo, tabManager: tabManager)
                .padding(8)

            Divider()

            // Session tree
            List {
                Section("Sessions") {
                    ForEach(repo.sessions) { session in
                        SessionRow(session: session, tabManager: tabManager, repo: repo)
                            .contextMenu {
                                Button("Connect") { tabManager.openTab(for: session) }
                                Button("Edit") { /* edit sheet */ }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    try? repo.delete(id: session.id)
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom actions
            HStack {
                Menu("Import") {
                    Button("Import JSON...") { importSessions(format: "json") }
                    Button("Import CSV...") { importSessions(format: "csv") }
                }
                .menuStyle(.borderlessButton)
                Menu("Export") {
                    Button("Export All as JSON...") { exportAll(format: "json") }
                }
                .menuStyle(.borderlessButton)
            }
            .padding(8)
        }
    }

    private func importSessions(format: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = format == "csv" ? [.commaSeparatedText] : [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = try? repo.importSessions(from: url)
    }

    private func exportAll(format: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ghostx_sessions.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? repo.exportSessions(ids: repo.sessions.map(\.id), to: url)
    }
}

/// Single session row in the sidebar
struct SessionRow: View {
    let session: SessionConfig
    @ObservedObject var tabManager: TabManager
    let repo: SessionRepository
    @State private var isConnecting = false

    var body: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundColor(tabManager.isConnected(session.id) ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.body)
                Text(session.connectionString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            tabManager.openTab(for: session)
        }
    }
}

/// Quick connect bar at the top of the sidebar
struct QuickConnectBar: View {
    @ObservedObject var repo: SessionRepository
    @ObservedObject var tabManager: TabManager
    @State private var input: String = ""
    @State private var showNewSession = false

    var body: some View {
        HStack(spacing: 4) {
            TextField("user@host:22", text: $input)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { quickConnect() }

            Button(action: quickConnect) {
                Image(systemName: "arrow.right")
            }
            .help("Quick Connect")

            Button(action: { showNewSession = true }) {
                Image(systemName: "plus")
            }
            .help("New Session")
        }
        .sheet(isPresented: $showNewSession) {
            NewSessionSheet(repo: repo, tabManager: tabManager, isPresented: $showNewSession)
        }
    }

    private func quickConnect() {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Parse "user@host:port" format
        var user = NSUserName()
        var host = trimmed
        var port: UInt16 = 22

        if let atIdx = trimmed.firstIndex(of: "@") {
            user = String(trimmed[..<atIdx])
            host = String(trimmed[trimmed.index(after: atIdx)...])
        }
        if let colonIdx = host.firstIndex(of: ":") {
            port = UInt16(host[host.index(after: colonIdx)...]) ?? 22
            host = String(host[..<colonIdx])
        }

        let config = SessionConfig(name: "", host: host, port: port, username: user)
        try? repo.save(config)
        tabManager.openTab(for: config)
        input = ""
    }
}
