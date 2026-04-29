import Foundation
import CoreGraphics

/// Terminal screen buffer - maintains a grid of character cells with SGR attributes
final class TerminalBuffer {
    struct Cell: Equatable {
        var character: Character = " "
        var fg: ANSIColor = .default
        var bg: ANSIColor = .default
        var bold: Bool = false
        var italic: Bool = false
        var underline: Bool = false
        var blink: Bool = false
        var inverse: Bool = false

        static let empty = Cell()

        var effectiveFg: ANSIColor {
            inverse ? bg : fg
        }
        var effectiveBg: ANSIColor {
            inverse ? fg : bg
        }
    }

    private(set) var cols: Int
    private(set) var rows: Int
    var cursorX: Int = 0
    var cursorY: Int = 0
    var cursorVisible: Bool = true
    var title: String = ""
    private(set) var grid: [[Cell]]
    private var scrollback: [[Cell]] = []
    private let maxScrollback: Int
    var palette: [CGColor] = ANSIColor.defaultPalette  // theme-overridable

    // Current SGR state (applied to new output)
    private var currentFg: ANSIColor = .default
    private var currentBg: ANSIColor = .default
    private var currentBold = false
    private var currentItalic = false
    private var currentUnderline = false
    private var currentBlink = false
    private var currentInverse = false

    // Scrollback viewing offset (0 = bottom/newest, positive = into history)
    private(set) var scrollOffset: Int = 0
    private var totalScrollback: Int { scrollback.count }

    func scroll(delta: Int) {
        scrollOffset = max(0, min(scrollOffset + delta, totalScrollback))
    }

    func resetScroll() {
        scrollOffset = 0
    }

    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0, (cols != self.cols || rows != self.rows) else { return }
        var newGrid: [[Cell]] = Array(repeating: Array(repeating: .empty, count: cols), count: rows)

        // Copy old content to new grid (keep what fits)
        for y in 0..<min(self.rows, rows) {
            for x in 0..<min(self.cols, cols) {
                newGrid[y][x] = grid[y][x]
            }
        }

        // Move overflow rows to scrollback
        if self.rows > rows {
            for y in rows..<self.rows {
                scrollback.append(grid[y])
            }
            while scrollback.count > maxScrollback { scrollback.removeFirst(min(100, scrollback.count)) }
        }

        self.cols = cols
        self.rows = rows
        self.grid = newGrid
        cursorX = min(cursorX, cols - 1)
        cursorY = min(cursorY, rows - 1)
    }

    init(cols: Int = 80, rows: Int = 24, maxScrollback: Int = 5000) {
        self.cols = cols
        self.rows = rows
        self.maxScrollback = maxScrollback
        self.grid = Array(repeating: Array(repeating: .empty, count: cols), count: rows)
    }

    // MARK: - Write text (with ANSI parsing)

    func write(_ data: Data) {
        guard let str = String(data: data, encoding: .utf8) else { return }
        scrollOffset = 0 // Auto-scroll to bottom on new output
        ANSIParser.parse(str) { [weak self] event in
            self?.handle(event)
        }
    }

    func writePlain(_ text: String) {
        for ch in text {
            putChar(ch)
        }
    }

    // MARK: - Handle parsed events

    private func handle(_ event: ANSIEvent) {
        switch event {
        case .print(let ch):
            putChar(ch)

        case .newline:
            cursorX = 0
            cursorDown()

        case .carriageReturn:
            cursorX = 0

        case .tab:
            let spaces = 8 - (cursorX % 8)
            for _ in 0..<spaces { putChar(" ") }

        case .backspace:
            if cursorX > 0 {
                cursorX -= 1
            }

        case .bell:
            break

        case .cursorUp(let n):
            cursorY = max(0, cursorY - n)

        case .cursorDown(let n):
            cursorY = min(rows - 1, cursorY + n)

        case .cursorForward(let n):
            cursorX = min(cols - 1, cursorX + n)

        case .cursorBack(let n):
            cursorX = max(0, cursorX - n)

        case .cursorPosition(let row, let col):
            cursorY = min(rows - 1, max(0, row - 1))
            cursorX = min(cols - 1, max(0, col - 1))

        case .eraseDisplay(let mode):
            eraseDisplay(mode)

        case .eraseLine(let mode):
            eraseLine(mode)

        case .setFg(let color):
            currentFg = mapColor(color)

        case .setFg256(let index):
            currentFg = .indexed(index)

        case .setFgTrue(let r, let g, let b):
            currentFg = .rgb(r, g, b)

        case .setBg(let color):
            currentBg = mapColor(color)

        case .setBg256(let index):
            currentBg = .indexed(index)

        case .setBgTrue(let r, let g, let b):
            currentBg = .rgb(r, g, b)

        case .setFgDefault:
            currentFg = .default

        case .setBgDefault:
            currentBg = .default

        case .setBold:
            currentBold = true

        case .setItalic:
            currentItalic = true

        case .setUnderline:
            currentUnderline = true

        case .setBlink:
            currentBlink = true

        case .setInverse:
            currentInverse = true

        case .resetAttributes:
            resetSGR()

        case .setTitle(let title):
            self.title = title

        case .setCursorVisible(let visible):
            cursorVisible = visible

        case .scrollUp(let n):
            scroll(by: n)

        case .scrollDown(let n):
            scroll(by: -n)

        case .setCursorStyle(_):
            break

        default:
            break
        }
    }

    // MARK: - Core operations

    private func putChar(_ ch: Character) {
        guard ch != "\u{7}" else { return } // skip BEL
        if ch == "\n" {
            cursorX = 0
            cursorDown()
            return
        }
        if ch == "\r" {
            cursorX = 0
            return
        }
        if ch == "\t" {
            let spaces = 8 - (cursorX % 8)
            for _ in 0..<spaces { putChar(" ") }
            return
        }
        if ch.asciiValue == 8 {
            if cursorX > 0 { cursorX -= 1 }
            return
        }
        guard ch.isASCII else { return }

        if cursorX >= cols {
            cursorX = 0
            cursorDown()
        }

        grid[cursorY][cursorX] = Cell(
            character: ch,
            fg: currentFg,
            bg: currentBg,
            bold: currentBold,
            italic: currentItalic,
            underline: currentUnderline,
            blink: currentBlink,
            inverse: currentInverse
        )
        cursorX += 1
    }

    private func cursorDown() {
        if cursorY < rows - 1 {
            cursorY += 1
        } else {
            scroll(by: 1)
        }
    }

    private func scroll(by n: Int) {
        if n > 0 {
            let moved = grid[0..<n]
            scrollback.append(contentsOf: moved)
            while scrollback.count > maxScrollback {
                scrollback.removeFirst(min(100, scrollback.count))
            }
            grid.removeFirst(n)
            grid.append(contentsOf: Array(repeating: Array(repeating: .empty, count: cols), count: n))
        } else if n < 0 {
            let count = -n
            grid.removeLast(count)
            grid.insert(contentsOf: Array(repeating: Array(repeating: .empty, count: cols), count: count), at: 0)
        }
    }

    private func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0: // cursor to end
            for x in cursorX..<cols { grid[cursorY][x] = .empty }
            for y in (cursorY + 1)..<rows { grid[y] = Array(repeating: .empty, count: cols) }
        case 1: // start to cursor
            for y in 0..<cursorY { grid[y] = Array(repeating: .empty, count: cols) }
            for x in 0...cursorX { grid[cursorY][x] = .empty }
        case 2, 3: // entire screen
            grid = Array(repeating: Array(repeating: .empty, count: cols), count: rows)
            cursorX = 0; cursorY = 0
        default: break
        }
    }

    private func eraseLine(_ mode: Int) {
        switch mode {
        case 0: // cursor to end
            for x in cursorX..<cols { grid[cursorY][x] = .empty }
        case 1: // start to cursor
            for x in 0...cursorX { grid[cursorY][x] = .empty }
        case 2: // entire line
            grid[cursorY] = Array(repeating: .empty, count: cols)
        default: break
        }
    }

    private func resetSGR() {
        currentFg = .default
        currentBg = .default
        currentBold = false
        currentItalic = false
        currentUnderline = false
        currentBlink = false
        currentInverse = false
    }

    private func mapColor(_ color: ANSIColorName) -> ANSIColor {
        switch color {
        case .black:   return .indexed(0)
        case .red:     return .indexed(1)
        case .green:   return .indexed(2)
        case .yellow:  return .indexed(3)
        case .blue:    return .indexed(4)
        case .magenta: return .indexed(5)
        case .cyan:    return .indexed(6)
        case .white:   return .indexed(7)
        case .brightBlack:   return .indexed(8)
        case .brightRed:     return .indexed(9)
        case .brightGreen:   return .indexed(10)
        case .brightYellow:  return .indexed(11)
        case .brightBlue:    return .indexed(12)
        case .brightMagenta: return .indexed(13)
        case .brightCyan:    return .indexed(14)
        case .brightWhite:   return .indexed(15)
        case .default: return .default
        }
    }

    /// Get snapshot for rendering
    func snapshot() -> TerminalSnapshot {
        // Build visible grid: mix scrollback + current grid based on scroll offset
        var visibleGrid: [[Cell]] = []
        let scrollRows = min(scrollOffset, scrollback.count)
        let usedScrollback = scrollRows > 0 ? Array(scrollback.suffix(scrollRows)) : []

        if scrollRows > 0 {
            visibleGrid = Array(usedScrollback.suffix(rows))
            if visibleGrid.count < rows {
                visibleGrid.append(contentsOf: grid.prefix(rows - visibleGrid.count))
            }
        } else {
            visibleGrid = grid
        }

        return TerminalSnapshot(
            cols: cols, rows: rows,
            grid: visibleGrid,
            cursorX: cursorX, cursorY: scrollRows > 0 ? -1 : cursorY,
            cursorVisible: scrollRows == 0 && cursorVisible,
            scrollbackCount: scrollback.count,
            title: title
        )
    }
}

struct TerminalSnapshot {
    let cols, rows: Int
    let grid: [[TerminalBuffer.Cell]]
    let cursorX, cursorY: Int
    let cursorVisible: Bool
    let scrollbackCount: Int
    let title: String
}

// MARK: - ANSI Color

enum ANSIColor: Equatable {
    case `default`
    case indexed(UInt8)
    case rgb(UInt8, UInt8, UInt8)

    func cgColor(palette: [CGColor]? = nil) -> CGColor {
        switch self {
        case .default: return .clear
        case .indexed(let idx): return Self.indexedToRGB(idx, palette: palette)
        case .rgb(let r, let g, let b): return CGColor(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, alpha: 1)
        }
    }

    var isDefault: Bool {
        if case .default = self { return true }
        return false
    }

    static let defaultPalette: [CGColor] = {
        let p: [(UInt8, UInt8, UInt8)] = [
            (0,0,0), (205,0,0), (0,205,0), (205,205,0),
            (0,0,238), (205,0,205), (0,205,205), (229,229,229),
            (127,127,127), (255,0,0), (0,255,0), (255,255,0),
            (92,92,255), (255,0,255), (0,255,255), (255,255,255)
        ]
        return p.map { CGColor(red: Double($0.0)/255, green: Double($0.1)/255, blue: Double($0.2)/255, alpha: 1) }
    }()

    static func indexedToRGB(_ idx: UInt8, palette: [CGColor]? = nil) -> CGColor {
        let pal = palette ?? defaultPalette
        if idx < pal.count {
            return pal[Int(idx)]
        }
        if idx < 232 {
            let i = Int(idx) - 16
            let r = UInt8((i / 36) * 51)
            let g = UInt8(((i / 6) % 6) * 51)
            let b = UInt8((i % 6) * 51)
            return CGColor(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, alpha: 1)
        }
        let gray = UInt8((Int(idx) - 232) * 10 + 8)
        return CGColor(red: Double(gray)/255, green: Double(gray)/255, blue: Double(gray)/255, alpha: 1)
    }
}

enum ANSIColorName {
    case black, red, green, yellow, blue, magenta, cyan, white
    case brightBlack, brightRed, brightGreen, brightYellow
    case brightBlue, brightMagenta, brightCyan, brightWhite
    case `default`
}
