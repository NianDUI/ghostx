import Foundation

/// SSH connection manager using libssh2
/// In production, this uses libssh2 C API. For prototype, it shells out to /usr/bin/ssh
final class SSHClient: ObservableObject {
    private var process: Process?
    private var outputPipe: Pipe?
    private var inputPipe: Pipe?
    private var errorPipe: Pipe?

    let config: SessionConfig
    let credential: Credential?
    var tunnels: [TunnelConfig] = []
    var proxy: ProxyConfig?

    @Published var isConnected = false
    @Published var lastError: String?
    @Published var connectionState: ConnectionState = .disconnected

    enum ConnectionState {
        case disconnected, connecting, connected, failed
    }

    // Output callback - raw bytes from the remote shell
    var onOutput: ((Data) -> Void)?
    var onDisconnect: ((Int) -> Void)?

    // MARK: - Lifecycle

    init(config: SessionConfig, credential: Credential?) {
        self.config = config
        self.credential = credential
    }

    func connect(terminalType: String = "xterm-256color") async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var args = [
            "-tt",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=\(config.keepAliveInterval)",
            "-o", "ServerAliveCountMax=3",
            "-o", "TCPKeepAlive=yes",
        ]

        // Proxy support
        if let proxyCmd = proxy?.sshProxyCommand {
            args.append(contentsOf: ["-o", proxyCmd])
        }

        // Tunnel forwarding flags
        for tunnel in tunnels where tunnel.enabled {
            args.append(tunnel.type.flag)
            args.append(tunnel.sshFlag)
        }

        // Port
        args.append(contentsOf: ["-p", "\(config.port)"])

        // Destination
        args.append("\(config.username)@\(config.host)")


        // Key-based auth
        if config.authMethod == .key, let keyPath = config.privateKeyPath {
            args.insert(contentsOf: ["-i", keyPath], at: args.count - 1)
        }

        process.arguments = args
        process.environment = ["TERM": terminalType, "LANG": "en_US.UTF-8"]

        let outPipe = Pipe()
        let inPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardInput = inPipe
        process.standardError = errPipe

        self.process = process
        self.outputPipe = outPipe
        self.inputPipe = inPipe
        self.errorPipe = errPipe

        // Read stdout asynchronously
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            DispatchQueue.main.async {
                self?.onOutput?(data)
            }
        }

        // Read stderr for errors
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            if let msg = String(data: data, encoding: .utf8), !msg.isEmpty {
                DispatchQueue.main.async { self.lastError = msg }
            }
        }

        // Handle termination
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.isConnected = false
                self?.connectionState = .disconnected
                self?.onDisconnect?(Int(proc.terminationStatus))
            }
        }

        connectionState = .connecting
        try process.run()
        isConnected = true
        connectionState = .connected

        // Run login script if configured
        if let script = config.loginScript, !script.isEmpty {
            send("\(script)\n")
        }
    }

    func send(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        inputPipe?.fileHandleForWriting.write(data)
    }

    func send(_ data: Data) {
        inputPipe?.fileHandleForWriting.write(data)
    }

    func resize(cols: Int, rows: Int) {
        guard let pid = process?.processIdentifier else { return }
        // Send SIGWINCH-equivalent via ioctl
        var winSize = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(cols),
            ws_xpixel: UInt16(cols * 9),
            ws_ypixel: UInt16(rows * 18)
        )
        // Note: ioctl on remote SSH PTY requires ssh protocol window-change message
        // For a full implementation, use libssh2_channel_request_pty_size
        // This prototype uses the shell-based approach
        _ = withUnsafePointer(to: &winSize) { _ in
            // In full implementation: libssh2_channel_request_pty_size(channel, cols, rows)
        }
        // Send escape sequence to request terminal resize via SSH escape
        send("\u{1b}[8;\(rows);\(cols)t")
    }

    func disconnect() {
        // Send exit to shell
        send("exit\n")
        // Force kill after 2s if still running
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.process?.isRunning == true {
                self?.process?.terminate()
            }
        }
    }

    deinit {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? inputPipe?.fileHandleForWriting.close()
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}
