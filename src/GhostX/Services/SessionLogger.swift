import Foundation

/// Logs terminal session I/O to timestamped files
final class SessionLogger {
    private let sessionID: UUID
    private let host: String
    private var logFile: FileHandle?
    private let dateFormatter: DateFormatter
    private(set) var isLogging = false
    let logURL: URL

    init(sessionID: UUID, host: String) {
        self.sessionID = sessionID
        self.host = host

        // Log directory: ~/Library/Logs/GhostX/
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/GhostX")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Log filename: host_2026-04-30_012345.log
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateStr = dateFormatter.string(from: Date())
        let safeHost = host.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
        logURL = logsDir.appendingPathComponent("\(safeHost)_\(dateStr).log")

        // Reuse formatter for timestamped lines
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    func start() {
        guard !isLogging else { return }
        FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: nil)
        logFile = try? FileHandle(forWritingTo: logURL)
        logFile?.seekToEndOfFile()
        isLogging = true
        writeHeader()
    }

    func logInput(_ text: String) {
        guard isLogging, let fh = logFile else { return }
        let ts = dateFormatter.string(from: Date())
        let line = "[\(ts)] <<< \(text)"
        fh.write((line + "\n").data(using: .utf8)!)
    }

    func logOutput(_ data: Data) {
        guard isLogging, let fh = logFile else { return }
        let ts = dateFormatter.string(from: Date())
        var line = "[\(ts)] >>> "
        if let str = String(data: data, encoding: .utf8) {
            line += str.replacingOccurrences(of: "\r", with: "\\r")
        } else {
            line += "<binary \(data.count) bytes>"
        }
        fh.write((line + "\n").data(using: .utf8)!)
    }

    func stop() {
        guard isLogging else { return }
        writeFooter()
        try? logFile?.synchronize()
        try? logFile?.close()
        logFile = nil
        isLogging = false
    }

    private func writeHeader() {
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let header = """
        === GhostX Session Log ===
        Session: \(sessionID.uuidString)
        Host: \(host)
        Started: \(dateFormatter.string(from: Date()))
        ===========================

        """
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        logFile?.write(header.data(using: .utf8)!)
    }

    private func writeFooter() {
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let footer = """

        ===========================
        Ended: \(dateFormatter.string(from: Date()))
        === End of Log ===
        """
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        logFile?.write(footer.data(using: .utf8)!)
    }

    deinit {
        stop()
    }
}
