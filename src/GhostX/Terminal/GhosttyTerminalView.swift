import SwiftUI
import AppKit

/// Ghostty-powered terminal view — replaces NativeTerminalView
/// Renders terminal content via libghostty-vt cells
final class GhosttyTerminalView: NSView {
    private let bridge: TerminalBridge
    private var font: CTFont
    private var fontSize: CGFloat
    private var cellWidth: CGFloat = 9
    private var cellHeight: CGFloat = 18
    private var theme: Theme = .dark
    private var themeObserver: NSObjectProtocol?
    private var cursorBlinkTimer: Timer?

    var onKeyPress: ((String) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    init(bridge: TerminalBridge, fontSize: CGFloat = 13) {
        self.bridge = bridge
        self.fontSize = fontSize
        self.font = CTFontCreateWithName("JetBrainsMono-Regular" as CFString, fontSize, nil)
        if CTFontGetSize(self.font) == 0 {
            self.font = CTFontCreateWithName("Menlo-Regular" as CFString, fontSize, nil)
        }
        if CTFontGetSize(self.font) == 0 {
            self.font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
                ?? CTFontCreateWithName("Monaco" as CFString, fontSize, nil)
        }
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        cellWidth = ceil(CTFontGetBoundingRectsForGlyphs(
            self.font, .default, [CTFontGetGlyphWithName(self.font, "M" as CFString)], nil, 1
        ).width)
        cellHeight = ceil(CTFontGetAscent(self.font) + CTFontGetDescent(self.font) + CTFontGetLeading(self.font))

        themeObserver = NotificationCenter.default.addObserver(
            forName: .init("GhostXThemeChanged"), object: nil, queue: .main
        ) { [weak self] note in
            if let t = note.object as? Theme { self?.theme = t; self?.needsDisplay = true }
        }

        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let cols = max(1, Int((newSize.width - 8) / cellWidth))
        let rows = max(1, Int((newSize.height - 8) / cellHeight))
        bridge.resize(cols: UInt16(cols), rows: UInt16(rows))
        onResize?(cols, rows)
    }

    func feedOutput(_ data: Data) {
        bridge.feedInput(data)
        DispatchQueue.main.async { self.needsDisplay = true }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(theme.bgCG)
        ctx.fill(dirtyRect)

        let cells = bridge.readScreenCells()
        for cell in cells {
            let x = CGFloat(cell.column) * cellWidth + 4
            let y = frame.height - CGFloat(cell.row + 1) * cellHeight - 4
            if x + cellWidth < dirtyRect.minX || x > dirtyRect.maxX { continue }
            if y + cellHeight < dirtyRect.minY || y > dirtyRect.maxY { continue }

            if !cell.bg.isDefault {
                ctx.setFillColor(cell.bg.cgColor(palette: theme.paletteCG))
                ctx.fill(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
            }

            if !cell.character.isEmpty && cell.character != " " {
                let str = NSAttributedString(string: cell.character, attributes: [
                    .font: cell.bold
                        ? (CTFontCreateCopyWithSymbolicTraits(font, 0, nil, .boldTrait, .boldTrait) ?? font)
                        : font,
                    .foregroundColor: cell.fg.isDefault
                        ? theme.fgCG : cell.fg.cgColor(palette: theme.paletteCG),
                ])
                let line = CTLineCreateWithAttributedString(str)
                let rect = CTLineGetImageBounds(line, ctx)
                let ty = y + (cellHeight - rect.height) / 2 - rect.origin.y
                ctx.textPosition = CGPoint(x: x, y: ty)
                CTLineDraw(line, ctx)
            }
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if let chars = event.characters { onKeyPress?(chars) }
        else { interpretKeyEvents([event]) }
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.copy, action: #selector(copyContent), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: L10n.paste, action: #selector(pasteContent), keyEquivalent: "v"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.selectAll, action: #selector(selectAllContent), keyEquivalent: "a"))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { pasteContent() }  // middle-click paste
    }

    @objc private func copyContent() {
        let cells = bridge.readScreenCells()
            .sorted { $0.row != $1.row ? $0.row < $1.row : $0.column < $1.column }
        var text = ""; var lastRow = 0; var lastCol: Int?
        for c in cells {
            // Blank lines between non-consecutive rows
            while lastRow < c.row {
                text += "\n"
                lastRow += 1
                lastCol = nil
            }
            // Pad to first column of row
            if lastCol == nil && c.column > 0 { text += String(repeating: " ", count: c.column); lastCol = c.column }
            // Pad between cells on same row
            while let lc = lastCol, c.column > lc + 1 { text += " "; lastCol = lc + 1 }
            text += c.character.isEmpty ? " " : c.character
            lastRow = c.row; lastCol = c.column
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func pasteContent() {
        guard let str = NSPasteboard.general.string(forType: .string) else { return }
        onKeyPress?(str)
    }

    @objc private func selectAllContent() {
        onKeyPress?("\u{1b}[1;1H")  // move cursor to top-left
    }

    override func scrollWheel(with event: NSEvent) {
        let d = event.scrollingDeltaY
        if d != 0 { bridge.scroll(delta: d > 0 ? -3 : 3); needsDisplay = true }
    }

    deinit {
        cursorBlinkTimer?.invalidate()
        if let o = themeObserver { NotificationCenter.default.removeObserver(o) }
    }
}

/// SwiftUI wrapper for GhosttyTerminalView
struct GhosttyTerminalDisplay: NSViewRepresentable {
    let bridge: TerminalBridge
    var onKeyPress: ((String) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    func makeNSView(context: Context) -> GhosttyTerminalView {
        let v = GhosttyTerminalView(bridge: bridge)
        v.onKeyPress = onKeyPress
        v.onResize = onResize
        return v
    }
    func updateNSView(_ v: GhosttyTerminalView, context: Context) {
        v.onKeyPress = onKeyPress; v.onResize = onResize
    }
}
