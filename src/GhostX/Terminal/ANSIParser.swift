import Foundation

/// Events emitted by the ANSI parser
enum ANSIEvent {
    case print(Character)
    case newline, carriageReturn, tab, backspace, bell
    case cursorUp(Int), cursorDown(Int), cursorForward(Int), cursorBack(Int)
    case cursorPosition(row: Int, col: Int)
    case eraseDisplay(Int), eraseLine(Int)
    case setFg(ANSIColorName), setFg256(UInt8), setFgTrue(UInt8, UInt8, UInt8)
    case setBg(ANSIColorName), setBg256(UInt8), setBgTrue(UInt8, UInt8, UInt8)
    case setFgDefault, setBgDefault
    case setBold, setItalic, setUnderline, setBlink, setInverse
    case resetAttributes
    case setTitle(String)
    case setCursorVisible(Bool)
    case setCursorStyle(Int)
    case scrollUp(Int), scrollDown(Int)
    case oscCommand(Int, String) // Operating System Command
    case ignore
}

/// Streaming ANSI escape sequence parser
enum ANSIParser {
    private enum State {
        case normal
        case escape     // saw ESC (0x1B)
        case csi        // saw ESC [
        case osc        // saw ESC ]
        case oscString  // reading OSC string
    }

    static func parse(_ input: String, handler: (ANSIEvent) -> Void) {
        var state = State.normal
        var params: [Int] = []
        var currentParam = ""
        var oscCommand = 0
        var oscString = ""
        var privateMarker = ""

        for ch in input {
            switch state {
            case .normal:
                switch ch {
                case "\u{1B}": // ESC
                    state = .escape
                case "\n": handler(.newline)
                case "\r": handler(.carriageReturn)
                case "\t": handler(.tab)
                case "\u{8}": handler(.backspace)
                case "\u{7}": handler(.bell)
                default: handler(.print(ch))
                }

            case .escape:
                switch ch {
                case "[":
                    state = .csi
                    params = []
                    currentParam = ""
                    privateMarker = ""
                case "]":
                    state = .osc
                    oscCommand = 0
                    oscString = ""
                case "7":
                    handler(.ignore) // DECSC - save cursor
                    state = .normal
                case "8":
                    handler(.ignore) // DECRC - restore cursor
                    state = .normal
                case "D":
                    handler(.cursorDown(1)) // IND
                    state = .normal
                case "M":
                    handler(.cursorUp(1)) // RI - reverse index
                    state = .normal
                default:
                    state = .normal
                }

            case .csi:
                switch ch {
                case "0"..."9":
                    currentParam.append(ch)
                case ";":
                    params.append(Int(currentParam) ?? 0)
                    currentParam = ""
                case "?", ">", "!":
                    privateMarker.append(ch)
                case let c where c.isLetter || "@`~".contains(c):
                    if !currentParam.isEmpty || (params.isEmpty && currentParam.isEmpty) {
                        params.append(Int(currentParam) ?? 0)
                    }
                    handleCSI(final: c, params: params, privateMarker: privateMarker, handler: handler)
                    state = .normal
                default:
                    break
                }

            case .osc:
                if ch.isNumber {
                    oscCommand = oscCommand * 10 + (ch.wholeNumberValue ?? 0)
                } else if ch == ";" {
                    state = .oscString
                } else {
                    state = .normal
                }

            case .oscString:
                if ch == "\u{7}" || ch == "\u{1B}" {
                    if oscCommand == 0 || oscCommand == 2 {
                        handler(.setTitle(oscString))
                    }
                    handler(.oscCommand(oscCommand, oscString))
                    state = ch == "\u{1B}" ? .escape : .normal
                } else {
                    oscString.append(ch)
                }
            }
        }
    }

    private static func handleCSI(final: Character, params: [Int], privateMarker: String,
                                   handler: (ANSIEvent) -> Void) {
        let n0 = params.count > 0 ? params[0] : 1
        let n1 = params.count > 1 ? params[1] : 0

        switch final {
        case "A": handler(.cursorUp(max(1, n0)))
        case "B": handler(.cursorDown(max(1, n0)))
        case "C": handler(.cursorForward(max(1, n0)))
        case "D": handler(.cursorBack(max(1, n0)))
        case "E": // CNL
            handler(.cursorDown(max(1, n0)))
            handler(.carriageReturn)
        case "F": // CPL
            handler(.cursorUp(max(1, n0)))
            handler(.carriageReturn)
        case "G": handler(.cursorPosition(row: n1, col: max(1, n0)))
        case "H", "f":
            handler(.cursorPosition(row: max(1, n0), col: max(1, n1)))
        case "J": handler(.eraseDisplay(n0))
        case "K": handler(.eraseLine(n0))
        case "L": handler(.scrollDown(n0 > 0 ? n0 : 1))
        case "M": handler(.scrollUp(n0 > 0 ? n0 : 1))
        case "P": handler(.ignore) // DCH
        case "@": handler(.ignore) // ICH
        case "S": handler(.scrollUp(max(1, n0)))
        case "T": handler(.scrollDown(max(1, n0)))
        case "h", "l":
            // Set/reset modes - mostly ignore for now
            if privateMarker == "?" {
                handleDECMode(n0, set: final == "h", handler: handler)
            }
        case "m": handleSGR(params, handler: handler)
        case "n":
            if n0 == 6 { /* cursor position report - ignored */ }
        case "r":
            // Set scrolling region - ignored for now
            handler(.ignore)
        case "X": handler(.ignore) // ECH
        case let c where c.isLowercase:
            handler(.ignore)
        default:
            handler(.ignore)
        }
    }

    private static func handleDECMode(_ mode: Int, set: Bool, handler: (ANSIEvent) -> Void) {
        switch mode {
        case 25: handler(.setCursorVisible(set))
        default: handler(.ignore)
        }
    }

    private static func handleSGR(_ params: [Int], handler: (ANSIEvent) -> Void) {
        if params.isEmpty || params == [0] {
            handler(.resetAttributes)
            return
        }
        var i = 0
        while i < params.count {
            let p = params[i]
            switch p {
            case 0: handler(.resetAttributes)
            case 1: handler(.setBold)
            case 3: handler(.setItalic)
            case 4: handler(.setUnderline)
            case 5: handler(.setBlink)
            case 7: handler(.setInverse)
            case 22: handler(.resetAttributes) // normal intensity
            case 23: handler(.setItalic) // reset italic via resetSGR ? just toggle
            case 24: handler(.resetAttributes) // not-underline handled by reset
            case 27: handler(.resetAttributes)
            case 30: handler(.setFg(.black))
            case 31: handler(.setFg(.red))
            case 32: handler(.setFg(.green))
            case 33: handler(.setFg(.yellow))
            case 34: handler(.setFg(.blue))
            case 35: handler(.setFg(.magenta))
            case 36: handler(.setFg(.cyan))
            case 37: handler(.setFg(.white))
            case 38:
                if i + 2 < params.count, params[i + 1] == 5 {
                    handler(.setFg256(UInt8(params[i + 2])))
                    i += 2
                } else if i + 4 < params.count, params[i + 1] == 2 {
                    handler(.setFgTrue(UInt8(params[i + 2]), UInt8(params[i + 3]), UInt8(params[i + 4])))
                    i += 4
                }
            case 39: handler(.setFgDefault)
            case 40: handler(.setBg(.black))
            case 41: handler(.setBg(.red))
            case 42: handler(.setBg(.green))
            case 43: handler(.setBg(.yellow))
            case 44: handler(.setBg(.blue))
            case 45: handler(.setBg(.magenta))
            case 46: handler(.setBg(.cyan))
            case 47: handler(.setBg(.white))
            case 48:
                if i + 2 < params.count, params[i + 1] == 5 {
                    handler(.setBg256(UInt8(params[i + 2])))
                    i += 2
                } else if i + 4 < params.count, params[i + 1] == 2 {
                    handler(.setBgTrue(UInt8(params[i + 2]), UInt8(params[i + 3]), UInt8(params[i + 4])))
                    i += 4
                }
            case 49: handler(.setBgDefault)
            case 90: handler(.setFg(.brightBlack))
            case 91: handler(.setFg(.brightRed))
            case 92: handler(.setFg(.brightGreen))
            case 93: handler(.setFg(.brightYellow))
            case 94: handler(.setFg(.brightBlue))
            case 95: handler(.setFg(.brightMagenta))
            case 96: handler(.setFg(.brightCyan))
            case 97: handler(.setFg(.brightWhite))
            case 100: handler(.setBg(.brightBlack))
            case 101: handler(.setBg(.brightRed))
            case 102: handler(.setBg(.brightGreen))
            case 103: handler(.setBg(.brightYellow))
            case 104: handler(.setBg(.brightBlue))
            case 105: handler(.setBg(.brightMagenta))
            case 106: handler(.setBg(.brightCyan))
            case 107: handler(.setBg(.brightWhite))
            default: break
            }
            i += 1
        }
    }
}
