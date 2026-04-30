import Foundation

/// Records terminal input as a script file that can be replayed
final class ScriptRecorder {
    enum Status { case idle, recording, paused }
    private(set) var status: Status = .idle

    private var scriptURL: URL?
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private var startTime: Date?

    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
    }

    var isRecording: Bool { status == .recording }

    func start(outputDir: URL? = nil) -> URL? {
        let dir = outputDir ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "ghostx_recording_\(dateFormatter.string(from: Date())).txt"
        scriptURL = dir.appendingPathComponent(filename)
        dateFormatter.dateFormat = "HH:mm:ss.SSS"

        FileManager.default.createFile(atPath: scriptURL!.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: scriptURL!)
        startTime = Date()
        status = .recording

        // Write header
        let header = "# GhostX Script Recording\n# Started: \(Date())\n# ===\n\n"
        fileHandle?.write(header.data(using: .utf8)!)
        return scriptURL
    }

    func recordInput(_ text: String) {
        guard status == .recording, let fh = fileHandle else { return }
        let ts = dateFormatter.string(from: Date())
        // Escape special chars for replay
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        let line = "[\(ts)] \(escaped)\n"
        fh.write(line.data(using: .utf8)!)
    }

    func pause() { if status == .recording { status = .paused } }
    func resume() { if status == .paused { status = .recording } }

    func stop() -> URL? {
        guard status != .idle else { return nil }
        // Write footer
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let footer = "\n# ===\n# Ended: \(Date())\n# Duration: \(String(format: "%.1f", elapsed))s\n"
        fileHandle?.write(footer.data(using: .utf8)!)
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        fileHandle = nil
        status = .idle
        return scriptURL
    }

    deinit { _ = stop() }
}
