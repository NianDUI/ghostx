import SwiftUI

/// Manages open terminal tabs
final class TabManager: ObservableObject {
    @Published var tabs: [TerminalTab] = []
    @Published var activeTabID: UUID?

    struct TerminalTab: Identifiable {
        let id: UUID
        let sessionID: UUID
        let title: String
        let config: SessionConfig
        var client: SSHClient
    }

    func openTab(for session: SessionConfig) {
        let credential = CredentialStore.shared.load(host: session.host, username: session.username)
        let client = SSHClient(config: session, credential: credential)
        let tab = TerminalTab(
            id: UUID(),
            sessionID: session.id,
            title: session.displayTitle,
            config: session,
            client: client
        )
        tabs.append(tab)
        activeTabID = tab.id

        Task {
            try? await client.connect()
        }
    }

    func closeTab(id: UUID) {
        if let tab = tabs.first(where: { $0.id == id }) {
            tab.client.disconnect()
        }
        tabs.removeAll { $0.id == id }
        if activeTabID == id {
            activeTabID = tabs.last?.id
        }
    }

    func activeClient() -> SSHClient? {
        guard let id = activeTabID else { return nil }
        return tabs.first(where: { $0.id == id })?.client
    }

    func isConnected(_ sessionID: UUID) -> Bool {
        tabs.contains { $0.sessionID == sessionID && $0.client.isConnected }
    }

    // Broadcast command to selected or all tabs
    func broadcastToAll(_ command: String) {
        guard !command.isEmpty else { return }
        for tab in tabs where tab.client.isConnected {
            tab.client.send("\(command)\n")
        }
    }

    func broadcast(command: String, to ids: Set<UUID>) {
        guard !command.isEmpty else { return }
        for tab in tabs where ids.contains(tab.id) && tab.client.isConnected {
            tab.client.send("\(command)\n")
        }
    }
}

/// Terminal area with tabs
struct TerminalArea: View {
    @ObservedObject var tabManager: TabManager

    var body: some View {
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
            VStack(spacing: 0) {
                // Tab bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(tabManager.tabs) { tab in
                            TabButton(
                                tab: tab,
                                isActive: tabManager.activeTabID == tab.id,
                                onSelect: { tabManager.activeTabID = tab.id },
                                onClose: { tabManager.closeTab(id: tab.id) }
                            )
                        }
                    }
                }
                .frame(height: 30)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

                // Active terminal
                if let activeTab = tabManager.tabs.first(where: { $0.id == tabManager.activeTabID }) {
                    TerminalView(client: activeTab.client, config: activeTab.config)
                }
            }
        }
    }
}

private func colorForState(_ state: SSHClient.ConnectionState) -> Color {
    switch state {
    case .disconnected: return .red
    case .connecting: return .yellow
    case .connected: return .green
    case .failed: return .orange
    }
}

/// Single tab button
struct TabButton: View {
    let tab: TabManager.TerminalTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForState(tab.client.connectionState))
                .frame(width: 6, height: 6)
            Text(tab.title)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color(NSColor.controlAccentColor).opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

/// Terminal view using native NSView rendering with ANSI support
struct TerminalView: View {
    @ObservedObject var client: SSHClient
    let config: SessionConfig
    @StateObject private var terminalState = TerminalState()
    @State private var logger: SessionLogger?
    @State private var triggerEngine: TriggerEngine?

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                TerminalDisplay(
                    buffer: terminalState.buffer,
                    onKeyPress: { key in
                        terminalState.buffer.resetScroll()
                        logger?.logInput(key)
                        client.send(key)
                    },
                    onResize: { cols, rows in
                        terminalState.resize(cols: cols, rows: rows)
                        client.resize(cols: cols, rows: rows)
                    }
                )
                .background(Color.black)
                .onAppear {
                let sz = geometry.size
                terminalState.updateFromFrame(width: sz.width, height: sz.height)

                // Start session logging
                let sessionLogger = SessionLogger(sessionID: config.id, host: config.host)
                sessionLogger.start()
                self.logger = sessionLogger

                // Setup trigger engine
                let engine = TriggerEngine()
                engine.setCallbacks(
                    notify: { title, body in
                        let notification = NSUserNotification()
                        notification.title = title
                        notification.informativeText = body
                        NSUserNotificationCenter.default.deliver(notification)
                    },
                    runCommand: { [weak client] cmd in
                        client?.send(cmd)
                    },
                    disconnect: { [weak client] in
                        client?.disconnect()
                    }
                )
                let triggerVM = TriggerConfigViewModel()
                triggerVM.load()
                engine.loadTriggers(triggerVM.triggers)
                self.triggerEngine = engine

                client.onOutput = { [weak terminalState, weak logger, weak engine] data in
                    terminalState?.buffer.write(data)
                    terminalState?.title = terminalState?.buffer.title ?? ""
                    logger?.logOutput(data)
                    engine?.feed(data)
                }
            }
                .onChange(of: geometry.size) { _, newSize in
                    terminalState.updateFromFrame(width: newSize.width, height: newSize.height)
                }
            }

            // Status bar
            HStack(spacing: 12) {
                Circle()
                    .fill(colorForState(client.connectionState))
                    .frame(width: 8, height: 8)
                Text(client.isConnected ? config.connectionString : "Disconnected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(terminalState.buffer.cols)×\(terminalState.buffer.rows)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Text(terminalState.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
}

/// Observable state holder for TerminalBuffer
class TerminalState: ObservableObject {
    let buffer = TerminalBuffer(cols: 80, rows: 24)
    @Published var title: String = ""
    private var currentCols = 80
    private var currentRows = 24
    private var titleObserver: NSObjectProtocol?

    func updateFromFrame(width: CGFloat, height: CGFloat) {
        let cellW: CGFloat = 9
        let cellH: CGFloat = 18
        let cols = max(1, Int((width - 8) / cellW))
        let rows = max(1, Int((height - 8) / cellH))
        resize(cols: cols, rows: rows)
    }

    func resize(cols: Int, rows: Int) {
        guard cols != currentCols || rows != currentRows else { return }
        currentCols = cols
        currentRows = rows
        buffer.resize(cols: cols, rows: rows)
    }
}

/// Bottom panel for composing batch commands with quick command support
struct ComposePanel: View {
    @ObservedObject var tabManager: TabManager
    @Binding var showPanel: Bool
    @State private var commandText: String = ""
    @State private var selectedTabIDs: Set<UUID> = []
    @State private var quickCommands: [QuickCommand] = []
    @State private var selectedQuickCmd: UUID?
    @State private var cmdName: String = ""
    private let repo = SessionRepository()

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Batch Command")
                    .font(.headline)
                Spacer()
                Text("\(selectedTabIDs.count) / \(tabManager.tabs.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Quick command picker
                Picker("Quick:", selection: $selectedQuickCmd) {
                    Text("Quick Commands").tag(nil as UUID?)
                    ForEach(quickCommands) { cmd in
                        Text(cmd.name).tag(cmd.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                .onChange(of: selectedQuickCmd) { _, newId in
                    if let id = newId, let cmd = quickCommands.first(where: { $0.id == id }) {
                        commandText = cmd.command
                    }
                }

                Button("Send to Selected") {
                    tabManager.broadcast(command: commandText, to: selectedTabIDs)
                }
                .disabled(commandText.isEmpty || selectedTabIDs.isEmpty)
                .buttonStyle(.borderedProminent)
                Button("Send to All") {
                    tabManager.broadcastToAll(commandText)
                }
                .disabled(commandText.isEmpty)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 8)

            // Multi-line command input
            TextEditor(text: $commandText)
                .font(.custom("JetBrainsMono-Regular", size: 12))
                .border(Color.secondary.opacity(0.3))
                .padding(.horizontal, 8)

            // Save quick command row
            HStack {
                TextField("Cmd name", text: $cmdName, prompt: Text("Save quick cmd as..."))
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button("Save") {
                    guard !cmdName.isEmpty && !commandText.isEmpty else { return }
                    let cmd = QuickCommand(name: cmdName, command: commandText)
                    try? repo.saveQuickCommand(cmd)
                    quickCommands = repo.loadQuickCommands()
                    cmdName = ""
                }
                .disabled(cmdName.isEmpty || commandText.isEmpty)
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)

            // Tab checkboxes for selection
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabManager.tabs) { tab in
                        Toggle(isOn: binding(for: tab.id)) {
                            Text(tab.title).font(.caption)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear { quickCommands = repo.loadQuickCommands() }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(get: { selectedTabIDs.contains(id) },
                set: { if $0 { selectedTabIDs.insert(id) } else { selectedTabIDs.remove(id) } })
    }
}
