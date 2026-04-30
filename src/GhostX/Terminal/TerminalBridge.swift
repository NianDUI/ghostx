import Foundation

/// Bridge to libghostty-vt C API — handles VT parsing + terminal state
/// Used by GhosttyTerminalView for rendering
final class TerminalBridge {
    static weak var activeBridge: TerminalBridge?
    private(set) var dylibLoaded = false
    private var terminalPtr: UnsafeMutableRawPointer?
    private var renderStatePtr: UnsafeMutableRawPointer?
    private var dylibHandle: UnsafeMutableRawPointer?
    private var scrollOffset: Int = 0

    private(set) var cols: UInt16
    private(set) var rows: UInt16
    let cellWidth: UInt32 = 9
    let cellHeight: UInt32 = 18
    private(set) var title: String = ""

    var onWriteToPty: ((Data) -> Void)?
    var onTitleChanged: ((String) -> Void)?
    var onScreenUpdate: (() -> Void)?

    init(cols: UInt16 = 80, rows: UInt16 = 24) {
        self.cols = cols; self.rows = rows
        loadDylib()
        self.terminalPtr = fn_terminal_new?(cols, rows, 100_000)
        self.renderStatePtr = fn_render_new?()

        if let t = terminalPtr {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            // Store self for C callbacks (called from ghostty C code)
            TerminalBridge.activeBridge = self
            fn_set_write_pty?(t, ctx, { ctxPtr, data, len in
                guard let ctxPtr, let data else { return }
                Unmanaged<TerminalBridge>.fromOpaque(ctxPtr).takeUnretainedValue()
                    .onWriteToPty?(Data(bytes: data, count: len))
            })
            fn_set_title_cb?(t, { ctxPtr, ptr, len in
                guard let ctxPtr, let ptr else { return }
                let ts = String(data: Data(bytes: ptr, count: len), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    let b = Unmanaged<TerminalBridge>.fromOpaque(ctxPtr).takeUnretainedValue()
                    b.title = ts; b.onTitleChanged?(ts)
                }
            })
        }
    }

    func feedInput(_ data: Data) {
        guard let t = terminalPtr else { return }
        scrollOffset = 0
        data.withUnsafeBytes { buf in
            guard let ptr = buf.bindMemory(to: UInt8.self).baseAddress else { return }
            fn_vt_write?(t, ptr, buf.count)
        }
        fn_render_update?(renderStatePtr, t)
        onScreenUpdate?()
    }

    func resize(cols: UInt16, rows: UInt16) {
        self.cols = cols; self.rows = rows
        fn_resize?(terminalPtr, cols, rows, cellWidth, cellHeight)
    }

    func scroll(delta: Int) {
        scrollOffset = max(0, scrollOffset + delta)
        // Notify ghostty terminal to scroll its internal viewport
        if let t = terminalPtr {
            fn_scroll_viewport?(t, Int32(-delta))
        }
    }

    func resetScroll() { scrollOffset = 0 }

    // Temp storage for row callback (avoid C callback capture issue)
    private var tempCells: [TerminalCellData] = []

    /// Read screen cells via libghostty-vt render state iterators
    func readScreenCells() -> [TerminalCellData] {
        guard let state = renderStatePtr, let terminal = terminalPtr else { return [] }
        fn_render_update?(state, terminal)

        tempCells = []
        guard let rowIter = fn_row_iter_new?(), let rowCells = fn_row_cells_new?() else { return [] }
        defer { fn_row_cells_free?(rowCells); fn_row_iter_free?(rowIter) }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let rowCallback: @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Void = {
            guard let ctx = $0, let cellsPtr = $2 else { return }
            let bridge = Unmanaged<TerminalBridge>.fromOpaque(ctx).takeUnretainedValue()
            // Apply scroll offset — skip rows before offset
            let displayRow = Int($1) - bridge.scrollOffset
            guard displayRow >= 0 else { return }
            var col: UInt32 = 0
            while bridge.fn_cells_next?(cellsPtr) == true {
                let len = bridge.fn_cell_grapheme_len?(cellsPtr) ?? 0
                if len > 0 {
                    var cp = [UInt32](repeating: 0, count: 4)
                    let n = bridge.fn_cell_graphemes?(cellsPtr, &cp, 4) ?? 0
                    let ch = String(cp.prefix(Int(n)).compactMap { UnicodeScalar($0) }.map(Character.init))
                    var fgT = (r: UInt8(0), g: UInt8(0), b: UInt8(0))
                    var bgT = (r: UInt8(0), g: UInt8(0), b: UInt8(0))
                    bridge.fn_cell_fg?(cellsPtr, &fgT.r, &fgT.g, &fgT.b)
                    bridge.fn_cell_bg?(cellsPtr, &bgT.r, &bgT.g, &bgT.b)
                    let flags = bridge.fn_cell_flags?(cellsPtr) ?? 0
                    bridge.tempCells.append(TerminalCellData(
                        row: displayRow, column: Int(col), character: ch,
                        fg: ANSIColor.rgb(fgT.r, fgT.g, fgT.b),
                        bg: ANSIColor.rgb(bgT.r, bgT.g, bgT.b),
                        bold: (flags & 1) != 0, italic: (flags & 2) != 0, underline: (flags & 4) != 0))
                }
                col += 1
            }
        }
        fn_get_rows?(state, rowIter, rowCells, rowCallback, ctx)

        return tempCells
    }

    // MARK: - Dylib loading

    private var fn_terminal_new: ((UInt16, UInt16, UInt32) -> UnsafeMutableRawPointer?)?
    private var fn_terminal_free: ((UnsafeMutableRawPointer?) -> Void)?
    private var fn_vt_write: ((UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int) -> Void)?
    private var fn_resize: ((UnsafeMutableRawPointer?, UInt16, UInt16, UInt32, UInt32) -> Void)?
    private var fn_render_new: (() -> UnsafeMutableRawPointer?)?
    private var fn_render_free: ((UnsafeMutableRawPointer?) -> Void)?
    private var fn_render_update: ((UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void)?
    private var fn_set_write_pty: ((UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int) -> Void) -> Void)?
    private var fn_set_title_cb: ((UnsafeMutableRawPointer?, @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Void) -> Void)?
    private var fn_row_iter_new: (() -> UnsafeMutableRawPointer?)?
    private var fn_row_cells_new: (() -> UnsafeMutableRawPointer?)?
    private var fn_row_iter_free: ((UnsafeMutableRawPointer?) -> Void)?
    private var fn_row_cells_free: ((UnsafeMutableRawPointer?) -> Void)?
    private var fn_cells_next: ((UnsafeMutableRawPointer?) -> Bool)?
    private var fn_cell_grapheme_len: ((UnsafeMutableRawPointer?) -> UInt32)?
    private var fn_cell_graphemes: ((UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?, UInt32) -> UInt32)?
    private var fn_cell_fg: ((UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?) -> Void)?
    private var fn_cell_bg: ((UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?) -> Void)?
    private var fn_get_rows: ((UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
        @convention(c) (UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Void, UnsafeMutableRawPointer?) -> Bool)?
    private var fn_scroll_viewport: ((UnsafeMutableRawPointer?, Int32) -> Void)?
    private var fn_cell_flags: ((UnsafeMutableRawPointer?) -> UInt32)?

    private func loadDylib() {
        let paths = [
            Bundle.main.path(forResource: "libghostty-vt", ofType: "dylib"),
            Bundle.main.bundlePath + "/Contents/MacOS/libghostty-vt.dylib",
            "/Users/lyd/WorkSpace/Ai/ghostx/build/ghostty/lib/libghostty-vt.dylib",
        ]
        var h: UnsafeMutableRawPointer?
        for p in paths { if let p, (h = dlopen(p, RTLD_NOW)) != nil { break } }
        guard let h else { return }
        dylibHandle = h

        // Verify ALL symbols used by the bridge before marking as loaded
        let required = [
            "ghostx_terminal_new", "ghostx_terminal_free", "ghostx_terminal_vt_write",
            "ghostx_terminal_resize", "ghostx_terminal_set_write_pty_callback",
            "ghostx_terminal_set_title_callback", "ghostx_terminal_scroll_viewport",
            "ghostx_render_state_new", "ghostx_render_state_free", "ghostx_render_state_update",
            "ghostx_row_iterator_new", "ghostx_row_cells_new",
            "ghostx_row_iterator_free", "ghostx_row_cells_free",
            "ghostx_render_state_get_rows", "ghostx_cells_next",
            "ghostx_cell_grapheme_len", "ghostx_cell_graphemes",
            "ghostx_cell_fg_color", "ghostx_cell_bg_color", "ghostx_cell_flags",
        ]
        for name in required { if dlsym(h, name) == nil { return } }
        dylibLoaded = true

        typealias T1 = @convention(c) (UInt16, UInt16, UInt32) -> UnsafeMutableRawPointer?
        typealias T2 = @convention(c) (UnsafeMutableRawPointer?) -> Void
        typealias T3 = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int) -> Void
        typealias T4 = @convention(c) (UnsafeMutableRawPointer?, UInt16, UInt16, UInt32, UInt32) -> Void
        typealias T5 = @convention(c) () -> UnsafeMutableRawPointer?
        typealias T6 = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        typealias T7 = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
        typealias T8 = @convention(c) (UnsafeMutableRawPointer?, @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int) -> Void) -> Void
        typealias T9 = @convention(c) (UnsafeMutableRawPointer?, @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int) -> Void) -> Void
        typealias T10 = @convention(c) (UnsafeMutableRawPointer?) -> Bool
        typealias T11 = @convention(c) (UnsafeMutableRawPointer?) -> UInt32
        typealias T12 = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?, UInt32) -> UInt32
        typealias T13 = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?) -> Void

        fn_terminal_new = resolve(h, "ghostx_terminal_new")
        fn_terminal_free = resolve(h, "ghostx_terminal_free")
        fn_vt_write = resolve(h, "ghostx_terminal_vt_write")
        fn_resize = resolve(h, "ghostx_terminal_resize")
        fn_render_new = resolve(h, "ghostx_render_state_new")
        fn_render_free = resolve(h, "ghostx_render_state_free")
        fn_render_update = resolve(h, "ghostx_render_state_update")
        fn_set_write_pty = resolve(h, "ghostx_terminal_set_write_pty_callback")
        fn_set_title_cb = resolve(h, "ghostx_terminal_set_title_callback")
        fn_row_iter_new = resolve(h, "ghostx_row_iterator_new")
        fn_row_cells_new = resolve(h, "ghostx_row_cells_new")
        fn_row_iter_free = resolve(h, "ghostx_row_iterator_free")
        fn_row_cells_free = resolve(h, "ghostx_row_cells_free")
        fn_get_rows = resolve(h, "ghostx_render_state_get_rows")
        fn_scroll_viewport = resolve(h, "ghostx_terminal_scroll_viewport")
        fn_cells_next = resolve(h, "ghostx_cells_next")
        fn_cell_grapheme_len = resolve(h, "ghostx_cell_grapheme_len")
        fn_cell_graphemes = resolve(h, "ghostx_cell_graphemes")
        fn_cell_fg = resolve(h, "ghostx_cell_fg_color")
        fn_cell_bg = resolve(h, "ghostx_cell_bg_color")
        fn_cell_flags = resolve(h, "ghostx_cell_flags")
    }

    private func resolve<T>(_ h: UnsafeMutableRawPointer, _ name: String, as: T.Type = T.self) -> T {
        unsafeBitCast(dlsym(h, name), to: T.self)
    }

    deinit {
        fn_render_free?(renderStatePtr)
        fn_terminal_free?(terminalPtr)
        if let h = dylibHandle { dlclose(h) }
    }
}

// Shared with old path — remove when NativeTerminalView is deprecated
struct TerminalCellData {
    let row, column: Int
    let character: String
    let fg: ANSIColor
    let bg: ANSIColor
    let bold, italic, underline: Bool
}
