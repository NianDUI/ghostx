import Foundation

/// Basic SFTP operations using system sftp command
/// In production, replace with libssh2 SFTP API
final class SFTPService {
    private let host: String
    private let port: UInt16
    private let username: String
    private let privateKeyPath: String?
    private var sftpProcess: Process?
    private var outputPipe: Pipe?
    private var inputPipe: Pipe?

    init(config: SessionConfig) {
        self.host = config.host
        self.port = config.port
        self.username = config.username
        self.privateKeyPath = config.privateKeyPath
    }

    /// List files in remote directory
    func listDirectory(_ path: String, completion: @escaping ([RemoteFile]) -> Void) {
        let args = buildArgs()
            + ["-b", "-",  // batch mode
               "\(username)@\(host)"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = args

        let outPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardInput = inPipe
        process.standardError = Pipe()

        var allOutput = ""
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8) {
                allOutput += str
            }
        }

        process.terminationHandler = { _ in
            let files = self.parseFileList(allOutput)
            DispatchQueue.main.async { completion(files) }
        }

        try? process.run()

        // Send ls command
        let cmd = "ls -la \"\(path)\"\nexit\n"
        inPipe.fileHandleForWriting.write(cmd.data(using: .utf8)!)
    }

    /// Download a file
    func download(_ remotePath: String, to localURL: URL, progress: @escaping (Double) -> Void,
                  completion: @escaping (Bool) -> Void) {
        let args = buildArgs()
            + ["-b", "-",
               "\(username)@\(host)"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = args

        let outPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardInput = inPipe
        process.standardError = Pipe()

        process.terminationHandler = { proc in
            DispatchQueue.main.async { completion(proc.terminationStatus == 0) }
        }

        try? process.run()

        let cmd = "lcd \"\(localURL.deletingLastPathComponent().path)\"\nget \"\(remotePath)\" \"\(localURL.lastPathComponent)\"\nexit\n"
        inPipe.fileHandleForWriting.write(cmd.data(using: .utf8)!)
    }

    /// Upload a file
    func upload(_ localPath: String, to remotePath: String, completion: @escaping (Bool) -> Void) {
        let args = buildArgs()
            + ["-b", "-",
               "\(username)@\(host)"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = args

        let inPipe = Pipe()
        process.standardInput = inPipe
        process.standardError = Pipe()

        process.terminationHandler = { proc in
            DispatchQueue.main.async { completion(proc.terminationStatus == 0) }
        }

        try? process.run()

        let cmd = "put \"\(localPath)\" \"\(remotePath)\"\nexit\n"
        inPipe.fileHandleForWriting.write(cmd.data(using: .utf8)!)
    }

    private func buildArgs() -> [String] {
        var args = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=yes",
            "-P", "\(port)",
        ]
        if let keyPath = privateKeyPath {
            args.append(contentsOf: ["-i", keyPath])
        }
        return args
    }

    private func parseFileList(_ output: String) -> [RemoteFile] {
        var files: [RemoteFile] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 9 else { continue }

            let permissions = parts[0]
            let name = parts[8]

            // Skip . and ..
            if name == "." || name == ".." { continue }

            let isDir = permissions.hasPrefix("d")
            let isLink = permissions.hasPrefix("l")

            // Parse size (5th field) - may contain non-numeric chars
            let sizeStr = parts.count > 4 ? parts[4] : "0"
            let size = Int64(sizeStr) ?? 0

            // Parse date (fields 5-7)
            let dateStr = parts.count > 7 ? "\(parts[5]) \(parts[6]) \(parts[7])" : ""

            files.append(RemoteFile(
                name: name,
                path: name,
                isDirectory: isDir,
                isSymlink: isLink,
                size: size,
                permissions: permissions,
                modificationDate: dateStr
            ))
        }
        return files
    }
}

struct RemoteFile: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: Int64
    let permissions: String
    let modificationDate: String

    var sizeFormatted: String {
        if isDirectory { return "--" }
        if size < 1024 { return "\(size) B" }
        if size < 1048576 { return String(format: "%.1f KB", Double(size) / 1024) }
        if size < 1073741824 { return String(format: "%.1f MB", Double(size) / 1048576) }
        return String(format: "%.1f GB", Double(size) / 1073741824)
    }

    var icon: String {
        if isDirectory { return "folder" }
        if isSymlink { return "link" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "sh", "py", "rb", "js", "ts", "go", "rs", "swift", "c", "cpp": return "chevron.left.forwardslash.chevron.right"
        case "zip", "tar", "gz", "bz2", "xz": return "doc.zipper"
        case "log", "txt", "md", "json", "xml", "yaml", "yml": return "doc.text"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}
