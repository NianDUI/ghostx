import Foundation
import Darwin

/// Native SSH client using libssh2 via dlopen.
final class Libssh2Client: ObservableObject {
    private var session: UnsafeMutableRawPointer?
    private var channel: UnsafeMutableRawPointer?
    private var sock: Int32 = -1
    private var dylib: UnsafeMutableRawPointer?
    private var readThread: Thread?
    private var shouldStop = false

    let config: SessionConfig
    @Published var isConnected = false
    @Published var lastError: String?
    @Published var state: SSHClient.ConnectionState = .disconnected
    var onOutput: ((Data) -> Void)?
    var onDisconnect: ((Int) -> Void)?
    var onPasswordRequired: ((String, String) -> String?)?  // (host, user) -> password
    private var autoReconnect = true
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3

    // Stored function pointers (non-optional for simplicity)
    typealias VoidFn = @convention(c) () -> Void
    typealias InitFn = @convention(c) (Int32) -> Int32
    typealias SessFn = @convention(c) () -> UnsafeMutableRawPointer?
    typealias FreeFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias HSFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    typealias DiscFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Int32
    typealias BlockFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    typealias AuthPwFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    typealias AuthKeyFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    typealias ChOpenFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias PtyFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Int32
    typealias PtySizeFn = @convention(c) (UnsafeMutableRawPointer?, Int32, Int32) -> Int32
    typealias ShellFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias ReadFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<CChar>?, Int) -> Int
    typealias WriteFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Int
    typealias EofFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias KaFn = @convention(c) (UnsafeMutableRawPointer?, Int32, UInt32) -> Int32
    typealias ErrFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias SetOptFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void

    private var _init: InitFn = { _ in -1 }
    private var _exit: VoidFn = {}
    private var _sessInit: SessFn = { nil }
    private var _sessFree: FreeFn = { _ in -1 }
    private var _handshake: HSFn = { _, _ in -1 }
    private var _disconnect: DiscFn = { _, _ in -1 }
    private var _setBlocking: BlockFn = { _, _ in }
    private var _authPassword: AuthPwFn = { _, _, _ in -1 }
    private var _authKey: AuthKeyFn = { _, _, _, _, _ in -1 }
    private var _channelOpen: ChOpenFn = { _ in nil }
    private var _channelClose: FreeFn = { _ in -1 }
    private var _channelFree: FreeFn = { _ in -1 }
    private var _requestPty: PtyFn = { _, _ in -1 }
    private var _ptySize: PtySizeFn = { _, _, _ in -1 }
    private var _shell: ShellFn = { _ in -1 }
    private var _channelRead: ReadFn = { _, _, _ in -1 }
    private var _channelWrite: WriteFn = { _, _, _ in -1 }
    private var _channelEof: EofFn = { _ in 0 }
    private var _keepaliveConfig: KaFn = { _, _, _ in -1 }
    private var _lastErrno: ErrFn = { _ in -1 }

    init(config: SessionConfig) {
        self.config = config
        loadLib()
    }

    private func loadLib() {
        let searchPaths = [
            "/opt/homebrew/lib/libssh2.1.dylib",
            "/opt/homebrew/lib/libssh2.dylib",
            Bundle.main.path(forResource: "libssh2", ofType: "dylib"),
        ]
        for p in searchPaths {
            dylib = dlopen(p, RTLD_NOW)
            if dylib != nil { break }
        }
        guard let h = dylib else {
            lastError = "libssh2.dylib not found"; return
        }
        _init       = getSym(h, "libssh2_init")
        _exit       = getSym(h, "libssh2_exit")
        _sessInit   = getSym(h, "libssh2_session_init")
        _sessFree   = getSym(h, "libssh2_session_free")
        _handshake  = getSym(h, "libssh2_session_handshake")
        _disconnect = getSym(h, "libssh2_session_disconnect")
        _setBlocking = getSym(h, "libssh2_session_set_blocking")
        _authPassword = getSym(h, "libssh2_userauth_password")
        _authKey     = getSym(h, "libssh2_userauth_publickey_fromfile")
        _channelOpen  = getSym(h, "libssh2_channel_open_session")
        _channelClose = getSym(h, "libssh2_channel_close")
        _channelFree  = getSym(h, "libssh2_channel_free")
        _requestPty   = getSym(h, "libssh2_channel_request_pty")
        _ptySize      = getSym(h, "libssh2_channel_request_pty_size")
        _shell        = getSym(h, "libssh2_channel_shell")
        _channelRead  = getSym(h, "libssh2_channel_read")
        _channelWrite = getSym(h, "libssh2_channel_write")
        _channelEof   = getSym(h, "libssh2_channel_eof")
        _keepaliveConfig = getSym(h, "libssh2_keepalive_config")
        _lastErrno    = getSym(h, "libssh2_session_last_errno")
        loadSftpSymbols(h)
    }

    private func getSym<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T {
        unsafeBitCast(dlsym(handle, name), to: T.self)
    }

    // MARK: - Connect

    func connect() {
        state = .connecting
        guard _init(0) == 0 else { fail("libssh2_init failed"); return }

        sock = connectSocket()
        guard sock >= 0 else { fail("Socket connect failed"); return }

        guard let s = _sessInit() else { fail("Session init failed"); return }
        session = s
        _setBlocking(s, 0)

        var rc = _handshake(s, sock)
        var tries = 0
        while rc == -37 && tries < 100 { // EAGAIN
            usleep(100_000)
            rc = _handshake(s, sock)
            tries += 1
        }
        guard rc == 0 else { fail("Handshake failed: err \(_lastErrno(s))"); return }

        // Auth
        if config.authMethod == .key, let kp = config.privateKeyPath {
            let path = (kp as NSString).expandingTildeInPath
            rc = _authKey(s, config.username, path + ".pub", path, nil)
        } else if let cred = CredentialStore.shared.load(host: config.host, username: config.username),
                  case .password(let pw) = cred.secret {
            rc = _authPassword(s, config.username, pw)
        } else if config.authMethod == .password {
            // Prompt for password via callback
            guard let password = onPasswordRequired?(config.host, config.username) else {
                fail("Password required"); return
            }
            rc = _authPassword(s, config.username, password)
        } else {
            fail("No credentials"); return
        }
        guard rc == 0 else { fail("Auth failed: err \(_lastErrno(s))"); return }

        guard let ch = _channelOpen(s) else { fail("Channel failed"); return }
        channel = ch
        _requestPty(ch, config.terminalType)
        _ptySize(ch, 80, 24)
        guard _shell(ch) == 0 else { fail("Shell failed"); return }
        _keepaliveConfig(s, 1, UInt32(config.keepAliveInterval))

        isConnected = true
        state = .connected
        reconnectAttempts = 0 // reset on successful connect
        shouldStop = false
        readThread = Thread { [weak self] in self?.readLoop() }
        readThread?.start()

        if let script = config.loginScript, !script.isEmpty { send("\(script)\n") }
    }

    private func fail(_ msg: String) {
        lastError = msg; state = .failed
    }

    private func readLoop() {
        var buf = [CChar](repeating: 0, count: 16384)
        while !shouldStop, let ch = channel {
            let n = _channelRead(ch, &buf, 16384)
            if n > 0 {
                let d = Data(bytes: buf, count: n)
                DispatchQueue.main.async { [weak self] in self?.onOutput?(d) }
            } else if n == -37 { usleep(10_000) }
            else if n < 0 { break }
            if _channelEof(ch) != 0 { break }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConnected = false
            self.state = .disconnected
            self.onDisconnect?(0)
            // Auto-reconnect
            if self.autoReconnect && self.reconnectAttempts < self.maxReconnectAttempts {
                self.reconnectAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.state = .connecting
                    self?.connect()
                }
            }
        }
    }

    func send(_ text: String) {
        guard let ch = channel, let d = text.data(using: .utf8) else { return }
        _ = d.withUnsafeBytes { _channelWrite(ch, $0.bindMemory(to: CChar.self).baseAddress, d.count) }
    }

    func send(_ data: Data) {
        guard let ch = channel else { return }
        _ = data.withUnsafeBytes { _channelWrite(ch, $0.bindMemory(to: CChar.self).baseAddress, data.count) }
    }

    func resize(cols: Int, rows: Int) {
        guard let ch = channel else { return }
        _ptySize(ch, Int32(cols), Int32(rows))
    }

    func disconnect() {
        shouldStop = true; isConnected = false; state = .disconnected
        if let ch = channel { _channelClose(ch); _channelFree(ch); channel = nil }
        if let s = session { _disconnect(s, "bye"); _sessFree(s); session = nil }
        if sock >= 0 { Darwin.close(sock); sock = -1 }
        _exit()
    }

    // MARK: - Socket

    private func connectSocket() -> Int32 {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM,
                              ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(config.host, "\(config.port)", &hints, &result) == 0, let info = result else { return -1 }
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

    // MARK: - SFTP

    private var _sftpInit: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?)? = nil
    private var _sftpShutdown: (@convention(c) (UnsafeMutableRawPointer?) -> Int32)? = nil
    private var _sftpOpen: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UInt64, Int64, Int32) -> UnsafeMutableRawPointer?)? = nil
    private var _sftpRead: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<CChar>?, Int) -> Int)? = nil
    private var _sftpWrite: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Int)? = nil
    private var _sftpClose: (@convention(c) (UnsafeMutableRawPointer?) -> Int32)? = nil
    private var _sftpOpendir: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?)? = nil
    private var _sftpReaddir: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<CChar>?, Int, UnsafeMutableRawPointer?) -> Int32)? = nil
    private var _sftpClosedir: (@convention(c) (UnsafeMutableRawPointer?) -> Int32)? = nil
    private var _sftpUnlink: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Int32)? = nil
    private var _sftpRename: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32)? = nil
    private var _sftpMkdir: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int64) -> Int32)? = nil
    private var _sftpStat: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Int32)? = nil

    private func loadSftpSymbols(_ h: UnsafeMutableRawPointer) {
        _sftpInit    = unsafeBitCast(dlsym(h, "libssh2_sftp_init"), to: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?).self)
        _sftpShutdown = unsafeBitCast(dlsym(h, "libssh2_sftp_shutdown"), to: (@convention(c) (UnsafeMutableRawPointer?) -> Int32).self)
        _sftpOpen    = unsafeBitCast(dlsym(h, "libssh2_sftp_open"), to: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UInt64, Int64, Int32) -> UnsafeMutableRawPointer?).self)
        _sftpRead    = unsafeBitCast(dlsym(h, "libssh2_sftp_read"), to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<CChar>?, Int) -> Int).self)
        _sftpWrite   = unsafeBitCast(dlsym(h, "libssh2_sftp_write"), to: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Int).self)
        _sftpClose   = unsafeBitCast(dlsym(h, "libssh2_sftp_close"), to: (@convention(c) (UnsafeMutableRawPointer?) -> Int32).self)
        _sftpOpendir = unsafeBitCast(dlsym(h, "libssh2_sftp_open_ex"), to: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?).self)
        _sftpReaddir = unsafeBitCast(dlsym(h, "libssh2_sftp_readdir"), to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<CChar>?, Int, UnsafeMutableRawPointer?) -> Int32).self)
        _sftpClosedir = unsafeBitCast(dlsym(h, "libssh2_sftp_close"), to: (@convention(c) (UnsafeMutableRawPointer?) -> Int32).self)
        _sftpUnlink  = unsafeBitCast(dlsym(h, "libssh2_sftp_unlink"), to: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Int32).self)
        _sftpRename  = unsafeBitCast(dlsym(h, "libssh2_sftp_rename"), to: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32).self)
        _sftpMkdir   = unsafeBitCast(dlsym(h, "libssh2_sftp_mkdir"), to: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int64) -> Int32).self)
        _sftpStat    = unsafeBitCast(dlsym(h, "libssh2_sftp_stat"), to: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Int32).self)
    }

    /// List files in remote directory
    func listDirectory(_ path: String) -> [RemoteFile] {
        guard let s = session, let initFn = _sftpInit,
              let sftp = initFn(s) else { return [] }
        defer { _sftpShutdown?(sftp) }

        guard let opendirFn = _sftpOpendir,
              let dir = opendirFn(sftp, path) else { return [] }
        defer { _sftpClosedir?(dir) }

        var files: [RemoteFile] = []
        var buf = [CChar](repeating: 0, count: 512)
        var attrs = LIBSSH2_SFTP_ATTRIBUTES()

        while let readdirFn = _sftpReaddir, readdirFn(dir, &buf, 512, &attrs) > 0 {
            let name = String(cString: buf)
            if name == "." || name == ".." { continue }
            let isDir = (attrs.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) != 0
                && (attrs.permissions & LIBSSH2_SFTP_S_IFDIR) != 0
            files.append(RemoteFile(
                name: name, path: name,
                isDirectory: isDir, isSymlink: false,
                size: Int64(attrs.filesize),
                permissions: String(format: "%o", attrs.permissions),
                modificationDate: "\(attrs.mtime)"
            ))
        }
        return files
    }

    /// Download a file from remote to local path
    func downloadFile(_ remotePath: String, to localPath: String) -> Bool {
        guard let s = session, let initFn = _sftpInit,
              let sftp = initFn(s) else { return false }
        defer { _sftpShutdown?(sftp) }

        guard let openFn = _sftpOpen,
              let readFn = _sftpRead,
              let closeFn = _sftpClose else { return false }

        let handle = openFn(sftp, remotePath,
            UInt64(LIBSSH2_FXF_READ), 0, LIBSSH2_SFTP_OPENFILE)
        guard let handle = handle else { return false }
        defer { closeFn(handle) }

        let fileData = NSMutableData()
        var buf = [CChar](repeating: 0, count: 32768)
        while true {
            let n = readFn(handle, &buf, 32768)
            if n > 0 { fileData.append(buf, length: n) }
            else if n == 0 { break }
            else if n < 0 { return false }
        }
        return fileData.write(toFile: localPath, atomically: true)
    }

    /// Upload a local file to remote
    func uploadFile(_ localPath: String, to remotePath: String) -> Bool {
        guard let s = session, let initFn = _sftpInit,
              let sftp = initFn(s) else { return false }
        defer { _sftpShutdown?(sftp) }

        guard let openFn = _sftpOpen,
              let writeFn = _sftpWrite,
              let closeFn = _sftpClose,
              let data = try? Data(contentsOf: URL(fileURLWithPath: localPath)) else { return false }

        let handle = openFn(sftp, remotePath,
            UInt64(LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC),
            Int64(LIBSSH2_SFTP_S_IRUSR | LIBSSH2_SFTP_S_IWUSR | LIBSSH2_SFTP_S_IRGRP | LIBSSH2_SFTP_S_IROTH),
            LIBSSH2_SFTP_OPENFILE)
        guard let handle = handle else { return false }
        defer { closeFn(handle) }

        let result = data.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.bindMemory(to: CChar.self).baseAddress else { return -1 }
            return writeFn(handle, base, data.count)
        }
        return result == data.count
    }

    deinit { disconnect(); if let h = dylib { dlclose(h) } }
}

// libssh2 SFTP constants
private let LIBSSH2_FXF_READ: Int32 = 0x0
private let LIBSSH2_FXF_WRITE: Int32 = 0x1
private let LIBSSH2_FXF_CREAT: Int32 = 0x8
private let LIBSSH2_FXF_TRUNC: Int32 = 0x10
private let LIBSSH2_SFTP_OPENFILE: Int32 = 0
private let LIBSSH2_SFTP_ATTR_PERMISSIONS: UInt64 = 0x08
private let LIBSSH2_SFTP_S_IFDIR: UInt64 = 0o040000
private let LIBSSH2_SFTP_S_IRUSR: Int64 = 0o0400
private let LIBSSH2_SFTP_S_IWUSR: Int64 = 0o0200
private let LIBSSH2_SFTP_S_IRGRP: Int64 = 0o0040
private let LIBSSH2_SFTP_S_IROTH: Int64 = 0o0004

struct LIBSSH2_SFTP_ATTRIBUTES {
    var flags: UInt64 = 0
    var filesize: UInt64 = 0
    var uid: UInt64 = 0; var gid: UInt64 = 0
    var permissions: UInt64 = 0
    var atime: UInt64 = 0; var mtime: UInt64 = 0
}
