import Foundation

/// Swift wrapper around libghostty-vt C API loaded dynamically at runtime.
/// This avoids SPM linker path issues during development.
final class TerminalBridge {
    private var terminalPtr: UnsafeMutableRawPointer?
    private var renderStatePtr: UnsafeMutableRawPointer?
    private var dylibHandle: UnsafeMutableRawPointer?

    private(set) var cols: UInt16
    private(set) var rows: UInt16
    let cellWidth: UInt32 = 9
    let cellHeight: UInt32 = 18

    var onWriteToPty: ((Data) -> Void)?
    var onTitleChanged: ((String) -> Void)?
    var onScreenUpdate: (() -> Void)?

    // Function pointers loaded from dylib
    private var fn_terminal_new: (@convention(c) (UInt16, UInt16, UInt32) -> UnsafeMutableRawPointer?)?
    private var fn_terminal_free: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
    private var fn_vt_write: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int) -> Void)?
    private var fn_terminal_resize: (@convention(c) (UnsafeMutableRawPointer?, UInt16, UInt16, UInt32, UInt32) -> Void)?
    private var fn_render_state_new: (@convention(c) () -> UnsafeMutableRawPointer?)?
    private var fn_render_state_free: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
    private var fn_render_state_update: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void)?
    // ... more as needed

    init(cols: UInt16 = 80, rows: UInt16 = 24) {
        self.cols = cols
        self.rows = rows
        loadDylib()
        self.terminalPtr = fn_terminal_new?(cols, rows, 5000)
        self.renderStatePtr = fn_render_state_new?()
    }

    private func loadDylib() {
        // Search for the dylib in multiple locations
        let searchPaths = [
            Bundle.main.resourcePath.map { "\($0)/../MacOS/libghostty-vt.dylib" },
            Bundle.main.bundlePath + "/Contents/MacOS/libghostty-vt.dylib",
            "/Users/lyd/WorkSpace/Ai/ghostx/src/GhostXBridge/libghostty-vt.dylib",
            "/Users/lyd/WorkSpace/Ai/ghostx/build/ghostty/lib/libghostty-vt.dylib",
        ]

        var handle: UnsafeMutableRawPointer?
        for path in searchPaths {
            guard let path = path else { continue }
            handle = dlopen(path, RTLD_NOW)
            if handle != nil { break }
        }

        guard let handle = handle else {
            print("[TerminalBridge] Warning: Could not load libghostty-vt.dylib - terminal features disabled")
            return
        }

        self.dylibHandle = handle

        fn_terminal_new = unsafeMakeFunc(handle, "ghostx_terminal_new")
        fn_terminal_free = unsafeMakeFunc(handle, "ghostx_terminal_free")
        fn_vt_write = unsafeMakeFunc(handle, "ghostx_terminal_vt_write")
        fn_terminal_resize = unsafeMakeFunc(handle, "ghostx_terminal_resize")
        fn_render_state_new = unsafeMakeFunc(handle, "ghostx_render_state_new")
        fn_render_state_free = unsafeMakeFunc(handle, "ghostx_render_state_free")
        fn_render_state_update = unsafeMakeFunc(handle, "ghostx_render_state_update")
    }

    /// Feed raw VT output into terminal parser
    func feedInput(_ data: Data) {
        guard let fn = fn_vt_write, let terminal = terminalPtr else { return }
        data.withUnsafeBytes { buf in
            guard let ptr = buf.bindMemory(to: UInt8.self).baseAddress else { return }
            fn(terminal, ptr, buf.count)
        }
        fn_render_state_update?(renderStatePtr, terminalPtr)
        onScreenUpdate?()
    }

    func resize(cols: UInt16, rows: UInt16) {
        self.cols = cols
        self.rows = rows
        fn_terminal_resize?(terminalPtr, cols, rows, cellWidth, cellHeight)
    }

    func processKeyboardInput(text: String) -> Data? {
        text.data(using: .utf8)
    }

    func readScreenCells() -> [TerminalCellData] {
        // Placeholder - full implementation reads via row/cell iterators
        return []
    }

    deinit {
        fn_render_state_free?(renderStatePtr)
        fn_terminal_free?(terminalPtr)
        if let handle = dylibHandle { dlclose(handle) }
    }
}

private func unsafeMakeFunc<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
    guard let sym = dlsym(handle, name) else { return nil }
    return unsafeBitCast(sym, to: T.self)
}

struct TerminalCellData {
    let row: Int
    let column: Int
    let character: String
    let fg: (r: UInt8, g: UInt8, b: UInt8)
    let bg: (r: UInt8, g: UInt8, b: UInt8)
    let bold, italic, underline: Bool
}
