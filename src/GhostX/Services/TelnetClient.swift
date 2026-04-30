import Foundation
import Darwin

/// Simple TELNET client for connecting to TELNET servers.
/// Implements basic RFC 854 TELNET protocol negotiation.
final class TelnetClient: ObservableObject {
    private var sock: Int32 = -1
    private var readThread: Thread?
    private var shouldStop = false

    let host: String
    let port: UInt16
    @Published var isConnected = false
    @Published var lastError: String?
    var onOutput: ((Data) -> Void)?
    var onDisconnect: ((Int) -> Void)?

    // TELNET protocol constants
    private static let IAC: UInt8 = 255
    private static let DONT: UInt8 = 254
    private static let DO: UInt8 = 253
    private static let WONT: UInt8 = 252
    private static let WILL: UInt8 = 251
    private static let SB: UInt8 = 250
    private static let SE: UInt8 = 240
    private static let ECHO: UInt8 = 1
    private static let SUP_GA: UInt8 = 3
    private static let TERM_TYPE: UInt8 = 24
    private static let NAWS: UInt8 = 31
    private static let LINEMODE: UInt8 = 34

    init(host: String, port: UInt16 = 23) {
        self.host = host
        self.port = port
    }

    func connect(terminalType: String = "xterm-256color") {
        sock = connectSocket()
        guard sock >= 0 else {
            lastError = "Failed to connect to \(host):\(port)"
            return
        }

        isConnected = true
        shouldStop = false
        readThread = Thread { [weak self] in self?.readLoop() }
        readThread?.start()
    }

    private func readLoop() {
        var buf = [UInt8](repeating: 0, count: 4096)
        var dataBuf = [UInt8]()
        var subnegotiation = false

        while !shouldStop {
            let n = Darwin.read(sock, &buf, 4096)
            if n <= 0 {
                if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) {
                    break
                }
                usleep(10_000)
                continue
            }

            var i = 0
            dataBuf.removeAll(keepingCapacity: true)

            while i < n {
                let b = buf[i]
                if subnegotiation {
                    if b == TelnetClient.SE { subnegotiation = false }
                    i += 1; continue
                }
                if b == TelnetClient.IAC {
                    if i + 1 < n {
                        let cmd = buf[i + 1]
                        switch cmd {
                        case TelnetClient.DO, TelnetClient.DONT, TelnetClient.WILL, TelnetClient.WONT:
                            if i + 2 < n {
                                handleNegotiation(cmd: cmd, option: buf[i + 2])
                                i += 3; continue
                            }
                        case TelnetClient.SB:
                            subnegotiation = true
                            i += 2; continue
                        default:
                            // Skip unknown IAC commands
                            i += 2; continue
                        }
                    } else {
                        break // Need more data
                    }
                } else {
                    dataBuf.append(b)
                }
                i += 1
            }

            if !dataBuf.isEmpty {
                let d = Data(dataBuf)
                DispatchQueue.main.async { [weak self] in self?.onOutput?(d) }
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.onDisconnect?(0)
        }
    }

    private func handleNegotiation(cmd: UInt8, option: UInt8) {
        var response: [UInt8] = [TelnetClient.IAC]
        switch cmd {
        case TelnetClient.DO:
            // Server wants us to do something
            switch option {
            case TelnetClient.SUP_GA, TelnetClient.ECHO:
                response.append(TelnetClient.WILL)
            default:
                response.append(TelnetClient.WONT)
            }
        case TelnetClient.WILL:
            // Server wants to do something
            switch option {
            case TelnetClient.SUP_GA, TelnetClient.ECHO:
                response.append(TelnetClient.DO)
            default:
                response.append(TelnetClient.DONT)
            }
        default:
            return
        }
        response.append(option)
        _ = Darwin.write(sock, response, response.count)
    }

    func send(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        send(data)
    }

    func send(_ data: Data) {
        guard sock >= 0 else { return }
        _ = data.withUnsafeBytes { ptr in
            Darwin.write(sock, ptr.bindMemory(to: UInt8.self).baseAddress, data.count)
        }
    }

    func resize(cols: Int, rows: Int) {
        // Send NAWS (Negotiate About Window Size) subnegotiation
        guard sock >= 0, cols > 0, rows > 0 else { return }
        var msg: [UInt8] = [
            TelnetClient.IAC, TelnetClient.SB, TelnetClient.NAWS,
            UInt8((cols >> 8) & 0xFF), UInt8(cols & 0xFF),
            UInt8((rows >> 8) & 0xFF), UInt8(rows & 0xFF),
            TelnetClient.IAC, TelnetClient.SE
        ]
        _ = Darwin.write(sock, &msg, msg.count)
    }

    func disconnect() {
        shouldStop = true
        isConnected = false
        if sock >= 0 { Darwin.close(sock); sock = -1 }
    }

    private func connectSocket() -> Int32 {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM,
                              ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "\(port)", &hints, &result) == 0, let info = result else { return -1 }
        defer { freeaddrinfo(result) }
        let fd = Darwin.socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return -1 }
        let fl = fcntl(fd, F_GETFL, 0)
        fcntl(fd, F_SETFL, fl | O_NONBLOCK)
        let cr = Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if cr < 0 && errno != EINPROGRESS { Darwin.close(fd); return -1 }
        var tv = timeval(tv_sec: 8, tv_usec: 0)
        var wfds = fd_set(fds_bits: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        let b = Int(fd)
        if b >= 0 && b < 1024 { wfds.fds_bits.0 |= (1 << b) }
        if Darwin.select(fd + 1, nil, &wfds, nil, &tv) <= 0 { Darwin.close(fd); return -1 }
        fcntl(fd, F_SETFL, fl)
        return fd
    }

    deinit { disconnect() }
}
