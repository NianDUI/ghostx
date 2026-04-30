import AppKit
import SwiftUI

/// Native AppKit view that renders a terminal buffer using CoreGraphics
final class NativeTerminalView: NSView {
    private let buffer: TerminalBuffer
    private var font: CTFont
    private var fontSize: CGFloat
    private var cellWidth: CGFloat = 0
    private var cellHeight: CGFloat = 0
    private var ascent: CGFloat = 0
    private var leading: CGFloat = 0
    private var theme: Theme = .dark
    private var defaultFg: CGColor { theme.fgCG }
    private var defaultBg: CGColor { theme.bgCG }
    private var cursorColor: CGColor { theme.cursorCG }
    private var palette: [CGColor] { theme.paletteCG }
    private var cursorBlinkTimer: Timer?
    private var themeObserver: NSObjectProtocol?
    private var horizontalScrollOffset: CGFloat = 0
    private var maxLineWidth: CGFloat = 0
    private var isSelectingColumn = false
    private var columnSelectStart = NSPoint.zero

    var onKeyPress: ((String) -> Void)?
    var onResize: ((Int, Int) -> Void)?  // cols, rows

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    init(buffer: TerminalBuffer, fontSize: CGFloat = 13) {
        self.buffer = buffer
        self.fontSize = fontSize
        self.font = CTFontCreateWithName("JetBrainsMono-Regular" as CFString, fontSize, nil)
        if CTFontGetSize(self.font) == 0 {
            self.font = CTFontCreateWithName("Menlo-Regular" as CFString, fontSize, nil)
        }
        if CTFontGetSize(self.font) == 0 {
            self.font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Monaco" as CFString, fontSize, nil)
        }

        super.init(frame: .zero)

        // Calculate cell dimensions
        let metrics = CTFontGetBoundingRectsForGlyphs(self.font, .default, [CTFontGetGlyphWithName(self.font, "M" as CFString)], nil, 1)
        cellWidth = ceil(metrics.width)
        cellHeight = ceil(CTFontGetAscent(self.font) + CTFontGetDescent(self.font) + CTFontGetLeading(self.font))
        ascent = CTFontGetAscent(self.font)
        leading = CTFontGetLeading(self.font)

        buffer.palette = theme.paletteCG
        updateFrame()

        // Listen for theme changes
        themeObserver = NotificationCenter.default.addObserver(forName: .init("GhostXThemeChanged"), object: nil, queue: .main) { [weak self] note in
            if let newTheme = note.object as? Theme {
                self?.theme = newTheme
                self?.buffer.palette = newTheme.paletteCG
                self?.needsDisplay = true
            }
        }

        // Cursor blink timer
        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.buffer.cursorVisible else { return }
                self.buffer.cursorVisible = false
                self.setNeedsCursorDisplay()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.buffer.cursorVisible = true
                    self?.setNeedsCursorDisplay()
                }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateFrame() {
        let w = CGFloat(buffer.cols) * cellWidth + 8
        let h = CGFloat(buffer.rows) * cellHeight + 8
        frame = NSRect(x: 0, y: 0, width: w, height: h)
    }

    private func setNeedsCursorDisplay() {
        let x = CGFloat(buffer.cursorX) * cellWidth + 4
        let y = frame.height - CGFloat(buffer.cursorY + 1) * cellHeight - 4
        setNeedsDisplay(NSRect(x: x, y: y, width: cellWidth, height: cellHeight))
    }

    func feedOutput(_ data: Data) {
        buffer.write(data)
        DispatchQueue.main.async { [weak self] in
            self?.needsDisplay = true
            self?.updateFrame()
        }
    }

    func resizeTerminal(cols: Int, rows: Int) {
        // Terminal resize - for now just redraw
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(defaultBg)
        ctx.fill(dirtyRect)

        let snapshot = buffer.snapshot()
        let hOffset = horizontalScrollOffset
        let startRow = max(0, Int(dirtyRect.origin.y / cellHeight) - 1)

        // Track max line width for horizontal scrollbar
        var maxW: CGFloat = 0
        for row in snapshot.grid { maxW = max(maxW, CGFloat(row.count) * cellWidth) }
        maxLineWidth = maxW

        let gridRows = snapshot.grid.count
        for y in startRow..<min(snapshot.rows, gridRows) {
            let screenY = frame.height - CGFloat(y + 1) * cellHeight - 4
            if screenY > dirtyRect.maxY || screenY + cellHeight < dirtyRect.minY { continue }

            let row = snapshot.grid[y]
            let rowCols = row.count
            for x in 0..<min(snapshot.cols, rowCols) {
                let cell = row[x]
                let screenX = CGFloat(x) * cellWidth + 4 - hOffset

                if screenX + cellWidth < dirtyRect.minX || screenX > dirtyRect.maxX { continue }

                // Draw background if not default
                if !cell.effectiveBg.isDefault {
                    ctx.setFillColor(cell.effectiveBg.cgColor(palette: palette))
                    ctx.fill(CGRect(x: screenX, y: screenY, width: cellWidth, height: cellHeight))
                }

                // Draw character
                if cell.character != " " {
                    let attrs: [NSAttributedString.Key: Any] = textAttributes(for: cell)
                    let str = NSAttributedString(string: String(cell.character), attributes: attrs)
                    let line = CTLineCreateWithAttributedString(str)
                    let lineRect = CTLineGetImageBounds(line, ctx)
                    let textY = screenY + (cellHeight - lineRect.height) / 2 - lineRect.origin.y
                    ctx.textPosition = CGPoint(x: screenX, y: textY)
                    CTLineDraw(line, ctx)
                }
            }
        }

        // Draw cursor
        if snapshot.cursorVisible {
            let cx = CGFloat(snapshot.cursorX) * cellWidth + 4 - hOffset
            let cy = frame.height - CGFloat(snapshot.cursorY + 1) * cellHeight - 4
            ctx.setFillColor(cursorColor)
            ctx.fill(CGRect(x: cx, y: cy, width: 2, height: cellHeight))
        }

        // Horizontal scrollbar
        let viewW = frame.width - 8
        if maxW > viewW && hOffset >= 0 {
            let barH: CGFloat = 6; let barY: CGFloat = 2
            let thumbW = max(20, viewW * (viewW / maxW))
            let maxOff = max(1, maxW - viewW)
            let thumbX = (viewW - thumbW) * (hOffset / maxOff)
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 0.5))
            ctx.fill(CGRect(x: 4 + thumbX, y: barY, width: thumbW, height: barH))
        }
    }

    private func textAttributes(for cell: TerminalBuffer.Cell) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [.font: font]

        // Foreground color - use palette if indexed
        let fgColor = cell.effectiveFg.isDefault ? defaultFg : cell.effectiveFg.cgColor(palette: palette)
        attrs[.foregroundColor] = fgColor

        // Bold - use bold font variant
        if cell.bold {
            if let boldFont = CTFontCreateCopyWithSymbolicTraits(font, 0, nil, .boldTrait, .boldTrait) {
                attrs[.font] = boldFont
            }
        }

        // Italic
        if cell.italic {
            if let italicFont = CTFontCreateCopyWithSymbolicTraits(font, 0, nil, .italicTrait, .italicTrait) {
                attrs[.font] = italicFont
            }
        }

        // Underline
        if cell.underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        return attrs
    }

    // MARK: - Resize

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let newCols = max(1, Int((newSize.width - 8) / cellWidth))
        let newRows = max(1, Int((newSize.height - 8) / cellHeight))
        if newCols != buffer.cols || newRows != buffer.rows {
            onResize?(newCols, newRows)
        }
    }

    func reconfigure(cols: Int, rows: Int) {
        // Buffer resize handled by TerminalState; just update frame
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags

        // Only intercept known special keys; pass everything else through
        let seq: String?
        switch event.keyCode {
        case 126: seq = mods.contains(.control) ? "\u{1b}[1;5A" : mods.contains(.option) ? "\u{1b}[1;3A" : "\u{1b}[A"
        case 125: seq = mods.contains(.control) ? "\u{1b}[1;5B" : mods.contains(.option) ? "\u{1b}[1;3B" : "\u{1b}[B"
        case 124: seq = mods.contains(.control) ? "\u{1b}[1;5C" : mods.contains(.option) ? "\u{1b}[1;3C" : "\u{1b}[C"
        case 123: seq = mods.contains(.control) ? "\u{1b}[1;5D" : mods.contains(.option) ? "\u{1b}[1;3D" : "\u{1b}[D"
        case 115: seq = "\u{1b}[H"
        case 119: seq = "\u{1b}[F"
        case 116: seq = "\u{1b}[5~"
        case 121: seq = "\u{1b}[6~"
        case 117: seq = "\u{1b}[3~"
        case 51:  seq = mods.contains(.option) ? "\u{1b}\u{7f}" : "\u{7f}"
        case 53:  seq = "\u{1b}"
        case 36:  seq = "\r"
        case 48:  seq = mods.contains(.shift) ? "\u{1b}[Z" : "\t"
        default:  seq = nil
        }

        if let s = seq {
            onKeyPress?(s)
        } else if let chars = event.characters {
            onKeyPress?(chars)
        } else {
            interpretKeyEvents([event])
        }
    }

    override func flagsChanged(with event: NSEvent) {}

    // MARK: - Mouse & Context Menu

    private var lastClickTime: TimeInterval = 0
    private var clickCount = 0

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        // Triple-click detection
        let now = event.timestamp
        if now - lastClickTime < 0.3 { clickCount += 1 } else { clickCount = 1 }
        lastClickTime = now

        if event.modifierFlags.contains(.option) {
            // Alt+drag: column/block selection start
            isSelectingColumn = true
            columnSelectStart = convert(event.locationInWindow, from: nil)
        } else if clickCount >= 3 {
            // Triple-click: select entire line
            let pos = convert(event.locationInWindow, from: nil)
            let row = Int((frame.height - pos.y - 4) / cellHeight)
            if row >= 0 && row < buffer.rows {
                // Select entire row via VT escape sequence
                onKeyPress?("\u{1b}[\(row+1);1H\u{1b}[?47h")
            }
            clickCount = 0
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isSelectingColumn {
            let pos = convert(event.locationInWindow, from: nil)
            let minX = min(columnSelectStart.x, pos.x)
            let maxX = max(columnSelectStart.x, pos.x)
            let minY = min(columnSelectStart.y, pos.y)
            let maxY = max(columnSelectStart.y, pos.y)

            let startCol = max(0, Int((minX - 4) / cellWidth))
            let endCol = max(0, Int((maxX - 4) / cellWidth))
            let startRow = max(0, Int((frame.height - maxY - 4) / cellHeight))
            let endRow = max(0, Int((frame.height - minY - 4) / cellHeight))

            // Build block selection text
            var selected: [String] = []
            for y in startRow...min(endRow, buffer.rows - 1) {
                var line = ""
                for x in startCol...min(endCol, buffer.cols - 1) {
                    line += String(buffer.snapshot().grid[min(y, buffer.rows-1)][min(x, buffer.cols-1)].character)
                }
                selected.append(line)
            }
            let text = selected.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                let pb = NSPasteboard.general; pb.clearContents(); pb.setString(text, forType: .string)
            }
        } else {
            // Normal drag
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isSelectingColumn { isSelectingColumn = false }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(copyToClipboard), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(pasteFromClipboard), keyEquivalent: "v"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(selectAllContent), keyEquivalent: "a"))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func otherMouseDown(with event: NSEvent) {
        // Middle button (buttonNumber 2) — paste by default
        if event.buttonNumber == 2 {
            pasteFromClipboard()
        }
    }

    @objc private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(buffer.snapshot().grid.flatMap { row in row.map { String($0.character) } + ["\n"] }.joined(), forType: .string)
    }

    @objc private func pasteFromClipboard() {
        guard let str = NSPasteboard.general.string(forType: .string) else { return }
        onKeyPress?(str)
    }

    @objc private func selectAllContent() {
        // Trigger select_all in terminal
        onKeyPress?("\u{1b}[1;1H\u{1b}[?47h")  // simplified select-all sequence
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            // Horizontal scroll with Shift
            let dx = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            horizontalScrollOffset = max(0, horizontalScrollOffset - dx)
            needsDisplay = true
        } else {
            let delta = event.scrollingDeltaY
            if delta != 0 {
                buffer.scroll(delta: delta > 0 ? -3 : 3)
                needsDisplay = true
            }
        }
    }

    deinit {
        cursorBlinkTimer?.invalidate()
        if let obs = themeObserver { NotificationCenter.default.removeObserver(obs) }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: CGFloat(buffer.cols) * cellWidth + 8,
            height: CGFloat(buffer.rows) * cellHeight + 8
        )
    }
}

// MARK: - SwiftUI wrapper

struct TerminalDisplay: NSViewRepresentable {
    let buffer: TerminalBuffer
    var onKeyPress: ((String) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    func makeNSView(context: Context) -> NativeTerminalView {
        let view = NativeTerminalView(buffer: buffer)
        view.onKeyPress = onKeyPress
        view.onResize = onResize
        return view
    }

    func updateNSView(_ nsView: NativeTerminalView, context: Context) {
        nsView.onKeyPress = onKeyPress
        nsView.onResize = onResize
    }
}
