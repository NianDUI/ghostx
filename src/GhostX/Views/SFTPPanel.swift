import SwiftUI

/// SFTP file browser panel for remote file management
struct SFTPPanel: View {
    let config: SessionConfig
    var nativeClient: Libssh2Client? = nil
    @State private var currentPath = "~"
    @State private var files: [RemoteFile] = []
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var selectedFiles: Set<String> = []
    @State private var showUploadPicker = false
    @State private var sortOrder: SortOrder = .name

    enum SortOrder { case name, size, date }

    private var service: SFTPService { SFTPService(config: config, nativeClient: nativeClient) }

    var body: some View {
        VStack(spacing: 0) {
            // Path bar
            HStack {
                Button(action: goUp) {
                    Image(systemName: "arrow.up")
                }
                .help("Go up")

                TextField("Path", text: $currentPath)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { refresh() }

                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .padding(8)

            // Sort header
            HStack {
                sortButton("Name", .name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                sortButton("Size", .size).frame(width: 80)
                sortButton("Date", .date).frame(width: 120)
            }
            .font(.caption.bold())
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)

            Divider()

            // File list
            List(files) { file in
                HStack {
                    Image(systemName: file.icon)
                        .foregroundColor(file.isDirectory ? .blue : .secondary)
                    Text(file.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(file.sizeFormatted)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Text(file.modificationDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if file.isDirectory {
                        enterDirectory(file)
                    }
                }
                .contextMenu {
                    if !file.isDirectory {
                        Button("Download...") { downloadFile(file) }
                    }
                }
            }
            .listStyle(.plain)

            Divider()

            // Bottom actions
            HStack {
                Button(action: { showUploadPicker = true }) {
                    Image(systemName: "arrow.up.doc")
                    Text("Upload")
                }
                .buttonStyle(.borderless)
                Spacer()
                if let error = errorMsg {
                    Text(error).font(.caption).foregroundColor(.red)
                }
            }
            .padding(8)
        }
        .frame(minWidth: 350, minHeight: 300)
        .onAppear { refresh() }
        .fileImporter(isPresented: $showUploadPicker, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                uploadFile(url)
            }
        }
    }

    private func sortButton(_ title: String, _ order: SortOrder) -> some View {
        Button(title) {
            sortOrder = order
        }
        .buttonStyle(.plain)
    }

    private func refresh() {
        isLoading = true
        errorMsg = nil
        service.listDirectory(currentPath) { result in
            isLoading = false
            files = result.sorted(by: sortComparator)
        }
    }

    private var sortComparator: (RemoteFile, RemoteFile) -> Bool {
        switch sortOrder {
        case .name:
            return { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            return { $0.size < $1.size }
        case .date:
            return { $0.modificationDate < $1.modificationDate }
        }
    }

    private func goUp() {
        if currentPath == "/" { return }
        currentPath = (currentPath as NSString).deletingLastPathComponent
        if currentPath.isEmpty { currentPath = "/" }
        refresh()
    }

    private func enterDirectory(_ file: RemoteFile) {
        currentPath = (currentPath as NSString).appendingPathComponent(file.name)
        refresh()
    }

    private func downloadFile(_ file: RemoteFile) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        if panel.runModal() == .OK, let url = panel.url {
            service.download(
                (currentPath as NSString).appendingPathComponent(file.name),
                to: url,
                progress: { _ in },
                completion: { success in
                    if !success { errorMsg = "Download failed" }
                }
            )
        }
    }

    private func uploadFile(_ localURL: URL) {
        let remotePath = (currentPath as NSString).appendingPathComponent(localURL.lastPathComponent)
        service.upload(localURL.path, to: remotePath) { success in
            if success { refresh() }
            else { errorMsg = "Upload failed" }
        }
    }
}

/// Inline SFTP panel that can be shown in split view or popover
struct SFTPPopover: View {
    let config: SessionConfig
    @State private var showSFTP = false

    var body: some View {
        Button(action: { showSFTP.toggle() }) {
            Image(systemName: "folder")
                .help("SFTP File Browser")
        }
        .popover(isPresented: $showSFTP) {
            SFTPPanel(config: config)
                .frame(width: 500, height: 400)
        }
    }
}
