import Foundation

/// Terminal renderer bridge using libghostty-vt C API via dlopen.
/// Used when full libghostty rendering is preferred over the built-in TerminalBuffer+NativeTerminalView.
/// Currently the built-in renderer is the primary path; this bridge is kept for future integration.
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

    // Function pointers
    private typealias TerminalNewFn = @convention(c) (UInt16, UInt16, UInt32) -> UnsafeMutableRawPointer?
    private typealias TerminalFreeFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias VtWriteFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int) -> Void
    private typealias ResizeFn = @convention(c) (UnsafeMutableRawPointer?, UInt16, UInt16, UInt32, UInt32) -> Void
    private typealias RenderNewFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias RenderFreeFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias RenderUpdateFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

    private var fn_terminal_new: TerminalNewFn?
    private var fn_terminal_free: TerminalFreeFn?
    private var fn_vt_write: VtWriteFn?
    private var fn_resize: ResizeFn?
    private var fn_render_new: RenderNewFn?
    private var fn_render_free: RenderFreeFn?
    private var fn_render_update: RenderUpdateFn?

    init(cols: UInt16 = 80, rows: UInt16 = 24) {
        self.cols = cols; self.rows = rows
        loadDylib()
        self.terminalPtr = fn_terminal_new?(cols, rows, 5000)
        self.renderStatePtr = fn_render_new?()
    }

    private func loadDylib() {
        let paths = [
            Bundle.main.path(forResource: "libghostty-vt", ofType: "dylib"),
            Bundle.main.bundlePath + "/Contents/MacOS/libghostty-vt.dylib",
            "/opt/homebrew/lib/libghostty-vt.dylib",
        ]
        var handle: UnsafeMutableRawPointer?
        for p in paths { if let p, (handle = dlopen(p, RTLD_NOW)) != nil { break } }
        guard let h = handle else { return }
        dylibHandle = h

        fn_terminal_new    = unsafeBitCast(dlsym(h, "ghostx_terminal_new"), to: TerminalNewFn?.self)
        fn_terminal_free   = unsafeBitCast(dlsym(h, "ghostx_terminal_free"), to: TerminalFreeFn?.self)
        fn_vt_write        = unsafeBitCast(dlsym(h, "ghostx_terminal_vt_write"), to: VtWriteFn?.self)
        fn_resize          = unsafeBitCast(dlsym(h, "ghostx_terminal_resize"), to: ResizeFn?.self)
        fn_render_new      = unsafeBitCast(dlsym(h, "ghostx_render_state_new"), to: RenderNewFn?.self)
        fn_render_free     = unsafeBitCast(dlsym(h, "ghostx_render_state_free"), to: RenderFreeFn?.self)
        fn_render_update   = unsafeBitCast(dlsym(h, "ghostx_render_state_update"), to: RenderUpdateFn?.self)
    }

    func feedInput(_ data: Data) {
        guard let fn = fn_vt_write, let t = terminalPtr else { return }
        data.withUnsafeBytes { buf in
            guard let ptr = buf.bindMemory(to: UInt8.self).baseAddress else { return }
            fn(t, ptr, buf.count)
        }
        fn_render_update?(renderStatePtr, terminalPtr)
        onScreenUpdate?()
    }

    func resize(cols: UInt16, rows: UInt16) {
        self.cols = cols; self.rows = rows
        fn_resize?(terminalPtr, cols, rows, cellWidth, cellHeight)
    }

    func processKeyboardInput(text: String) -> Data? { text.data(using: .utf8) }

    func readScreenCells() -> [TerminalCellData] {
        // Full implementation using row/cell iterators from libghostty-vt
        // See ghostty_bridge.c for the C API surface
        []
    }

    deinit {
        fn_render_free?(renderStatePtr)
        fn_terminal_free?(terminalPtr)
        if let h = dylibHandle { dlclose(h) }
    }
}

struct TerminalCellData {
    let row, column: Int
    let character: String
    let fg: (r: UInt8, g: UInt8, b: UInt8)
    let bg: (r: UInt8, g: UInt8, b: UInt8)
    let bold, italic, underline: Bool
}
