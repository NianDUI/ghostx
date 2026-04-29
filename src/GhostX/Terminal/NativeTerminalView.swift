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

        // Background
        ctx.setFillColor(defaultBg)
        ctx.fill(dirtyRect)

        let snapshot = buffer.snapshot()
        let startRow = max(0, Int(dirtyRect.origin.y / cellHeight) - 1)

        for y in startRow..<snapshot.rows {
            let screenY = frame.height - CGFloat(y + 1) * cellHeight - 4
            if screenY > dirtyRect.maxY || screenY + cellHeight < dirtyRect.minY { continue }

            for x in 0..<snapshot.cols {
                let cell = snapshot.grid[y][x]
                let screenX = CGFloat(x) * cellWidth + 4

                // Skip cells outside dirty rect
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
            let cx = CGFloat(snapshot.cursorX) * cellWidth + 4
            let cy = frame.height - CGFloat(snapshot.cursorY + 1) * cellHeight - 4
            ctx.setFillColor(cursorColor)
            ctx.fill(CGRect(x: cx, y: cy, width: 2, height: cellHeight))
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
        // Handle special keys first
        let mods = event.modifierFlags
        switch event.keyCode {
        case 126: // Up arrow
            onKeyPress?(mods.contains(.control) ? "\u{1b}[1;5A" : mods.contains(.option) ? "\u{1b}[1;3A" : "\u{1b}[A")
            return
        case 125: // Down arrow
            onKeyPress?(mods.contains(.control) ? "\u{1b}[1;5B" : mods.contains(.option) ? "\u{1b}[1;3B" : "\u{1b}[B")
            return
        case 124: // Right arrow
            onKeyPress?(mods.contains(.control) ? "\u{1b}[1;5C" : mods.contains(.option) ? "\u{1b}[1;3C" : "\u{1b}[C")
            return
        case 123: // Left arrow
            onKeyPress?(mods.contains(.control) ? "\u{1b}[1;5D" : mods.contains(.option) ? "\u{1b}[1;3D" : "\u{1b}[D")
            return
        case 115: // Home
            onKeyPress?("\u{1b}[H")
            return
        case 119: // End
            onKeyPress?("\u{1b}[F")
            return
        case 116: // Page Up
            onKeyPress?("\u{1b}[5~")
            return
        case 121: // Page Down
            onKeyPress?("\u{1b}[6~")
            return
        case 117: // Delete (forward)
            onKeyPress?("\u{1b}[3~")
            return
        case 51: // Backspace/Delete
            onKeyPress?(mods.contains(.option) ? "\u{1b}\u{7f}" : "\u{7f}")
            return
        case 53: // Escape
            onKeyPress?("\u{1b}")
            return
        case 36: // Return
            onKeyPress?("\r")
            return
        case 48: // Tab
            onKeyPress?(mods.contains(.shift) ? "\u{1b}[Z" : "\t")
            return
        default: break
        }

        // Regular text input
        if let chars = event.characters {
            onKeyPress?(chars)
        } else {
            interpretKeyEvents([event])
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // Handle modifier-only events
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        if delta != 0 {
            buffer.scroll(delta: delta > 0 ? -3 : 3)
            needsDisplay = true
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
