import SwiftUI
import UniformTypeIdentifiers

/// Dual-pane SFTP panel: local filesystem (left) + remote (right)
struct SFTPDualPane: View {
    let config: SessionConfig
    var nativeClient: Libssh2Client? = nil
    @State private var localPath: String = NSHomeDirectory()
    @State private var remotePath: String = "~"
    @State private var localFiles: [LocalFile] = []
    @State private var remoteFiles: [RemoteFile] = []
    @State private var selectedLocal: Set<String> = []
    @State private var selectedRemote: Set<String> = []
    @State private var transfers: [TransferItem] = []
    @State private var isLoading = false
    @State private var errorMsg: String?

    private var service: SFTPService { SFTPService(config: config, nativeClient: nativeClient) }

    var body: some View {
        VStack(spacing: 0) {
            // Transfer queue (collapsed when empty)
            if !transfers.isEmpty {
                transferQueueView
                Divider()
            }

            // Dual panes
            HSplitView {
                localPane
                remotePane
            }

            // Status bar
            HStack {
                if let err = errorMsg { Text(err).font(.caption).foregroundColor(.red) }
                Spacer()
                Text("\(selectedLocal.count + selectedRemote.count) selected")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 2)
        }
        .frame(minHeight: 250, idealHeight: 350)
        .onAppear { loadLocal(); loadRemote() }
    }

    // MARK: - Local pane

    private var localPane: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "desktopcomputer").foregroundColor(.blue)
                Text("Local").font(.caption.bold())
                Spacer()
                Button(action: goUpLocal) {
                    Image(systemName: "arrow.up").font(.caption)
                }.buttonStyle(.borderless).disabled(localPath == "/")
            }
            .padding(.horizontal, 8).padding(.vertical, 2)

            TextField("", text: $localPath, prompt: Text("/path"))
                .font(.caption).textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)
                .onSubmit { loadLocal() }

            Divider()

            List(localFiles) { file in
                HStack {
                    Image(systemName: file.icon)
                        .foregroundColor(file.isDirectory ? .blue : .secondary)
                    Text(file.name).font(.caption).lineLimit(1)
                    Spacer()
                    Text(file.sizeFormatted).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if file.isDirectory {
                        localPath = file.path
                        loadLocal()
                    }
                }
                .onTapGesture {
                    if selectedLocal.contains(file.path) {
                        selectedLocal.remove(file.path)
                    } else {
                        selectedLocal.insert(file.path)
                    }
                }
                .background(selectedLocal.contains(file.path) ? Color.accentColor.opacity(0.2) : Color.clear)
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 200)
    }

    // MARK: - Remote pane

    private var remotePane: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "server.rack").foregroundColor(.green)
                Text("Remote").font(.caption.bold())
                Spacer()
                Button(action: goUpRemote) {
                    Image(systemName: "arrow.up").font(.caption)
                }.buttonStyle(.borderless).disabled(remotePath == "/" || remotePath == "~")
                Button(action: loadRemote) {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 8).padding(.vertical, 2)

            TextField("", text: $remotePath, prompt: Text("/remote/path"))
                .font(.caption).textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)
                .onSubmit { loadRemote() }

            Divider()

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(remoteFiles) { file in
                    HStack {
                        Image(systemName: file.icon)
                            .foregroundColor(file.isDirectory ? .blue : .secondary)
                        Text(file.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(file.sizeFormatted).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if file.isDirectory {
                            remotePath = (remotePath as NSString).appendingPathComponent(file.name)
                            loadRemote()
                        }
                    }
                    .onTapGesture {
                        if selectedRemote.contains(file.path) {
                            selectedRemote.remove(file.path)
                        } else {
                            selectedRemote.insert(file.path)
                        }
                    }
                    .background(selectedRemote.contains(file.path) ? Color.accentColor.opacity(0.2) : Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 200)
    }

    // MARK: - Transfer queue

    private var transferQueueView: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Transfers").font(.caption.bold())
                Spacer()
                Text("\(transfers.filter { $0.status == .done }.count)/\(transfers.count)").font(.caption).foregroundColor(.secondary)
                Button("Clear") { transfers.removeAll() }.font(.caption).buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)

            ForEach(transfers) { item in
                HStack(spacing: 4) {
                    Image(systemName: item.direction == .upload ? "arrow.up" : "arrow.down")
                        .foregroundColor(item.status == .done ? .green : item.status == .failed ? .red : .blue)
                    Text(item.name).font(.caption).lineLimit(1)
                    Spacer()
                    if item.status == .transferring {
                        ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                    } else {
                        Text(item.status.label).font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 4)
        .frame(height: min(CGFloat(transfers.count * 24 + 28), 80))
    }

    // MARK: - Actions

    private func loadLocal() {
        let url = URL(fileURLWithPath: localPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return }
        localFiles = contents.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return LocalFile(name: url.lastPathComponent, path: url.path, isDirectory: isDir, size: size)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func loadRemote() {
        isLoading = true
        service.listDirectory(remotePath) { files in
            isLoading = false
            remoteFiles = files
        }
    }

    private func goUpLocal() {
        localPath = (localPath as NSString).deletingLastPathComponent
        if localPath.isEmpty { localPath = "/" }
        loadLocal()
    }

    private func goUpRemote() {
        remotePath = (remotePath as NSString).deletingLastPathComponent
        if remotePath.isEmpty { remotePath = "/" }
        loadRemote()
    }
}

// MARK: - Local file model

struct LocalFile: Identifiable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int

    var sizeFormatted: String {
        if isDirectory { return "--" }
        if size < 1024 { return "\(size) B" }
        if size < 1048576 { return String(format: "%.1f KB", Double(size)/1024) }
        return String(format: "%.1f MB", Double(size)/1048576)
    }

    var icon: String {
        if isDirectory { return "folder" }
        switch (name as NSString).pathExtension.lowercased() {
        case "sh","py","rb","js","ts","go","rs","swift","c","cpp": return "chevron.left.forwardslash.chevron.right"
        case "zip","tar","gz": return "doc.zipper"
        case "pdf": return "doc.richtext"
        case "log","txt","md","json","xml","yaml": return "doc.text"
        default: return "doc"
        }
    }
}

// MARK: - Transfer item

struct TransferItem: Identifiable {
    let id = UUID()
    let name: String
    let direction: Direction
    var status: Status = .pending

    enum Direction { case upload, download }
    enum Status {
        case pending, transferring, done, failed
        var label: String {
            switch self {
            case .pending: return "pending"
            case .transferring: return "transferring..."
            case .done: return "done"
            case .failed: return "failed"
            }
        }
    }
}
