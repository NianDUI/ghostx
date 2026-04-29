import SwiftUI

/// Terminal color theme
struct Theme: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var author: String = ""
    var foreground: HexColor = .init(red: 0.867, green: 0.867, blue: 0.867)
    var background: HexColor = .init(red: 0, green: 0, blue: 0)
    var cursor: HexColor = .init(red: 1, green: 1, blue: 1)
    var selection: HexColor = .init(red: 0.3, green: 0.3, blue: 0.3, alpha: 0.5)
    var ansiBlack: HexColor = .init(red: 0, green: 0, blue: 0)
    var ansiRed: HexColor = .init(red: 0.804, green: 0, blue: 0)
    var ansiGreen: HexColor = .init(red: 0, green: 0.804, blue: 0)
    var ansiYellow: HexColor = .init(red: 0.804, green: 0.804, blue: 0)
    var ansiBlue: HexColor = .init(red: 0, green: 0, blue: 0.933)
    var ansiMagenta: HexColor = .init(red: 0.804, green: 0, blue: 0.804)
    var ansiCyan: HexColor = .init(red: 0, green: 0.804, blue: 0.804)
    var ansiWhite: HexColor = .init(red: 0.898, green: 0.898, blue: 0.898)
    var ansiBrightBlack: HexColor = .init(red: 0.5, green: 0.5, blue: 0.5)
    var ansiBrightRed: HexColor = .init(red: 1, green: 0, blue: 0)
    var ansiBrightGreen: HexColor = .init(red: 0, green: 1, blue: 0)
    var ansiBrightYellow: HexColor = .init(red: 1, green: 1, blue: 0)
    var ansiBrightBlue: HexColor = .init(red: 0.361, green: 0.361, blue: 1)
    var ansiBrightMagenta: HexColor = .init(red: 1, green: 0, blue: 1)
    var ansiBrightCyan: HexColor = .init(red: 0, green: 1, blue: 1)
    var ansiBrightWhite: HexColor = .init(red: 1, green: 1, blue: 1)

    var bgCG: CGColor { background.cgColor }
    var fgCG: CGColor { foreground.cgColor }
    var cursorCG: CGColor { cursor.cgColor }

    var paletteCG: [CGColor] { [
        ansiBlack, ansiRed, ansiGreen, ansiYellow, ansiBlue, ansiMagenta, ansiCyan, ansiWhite,
        ansiBrightBlack, ansiBrightRed, ansiBrightGreen, ansiBrightYellow,
        ansiBrightBlue, ansiBrightMagenta, ansiBrightCyan, ansiBrightWhite,
    ].map(\.cgColor) }

    static let dark = Theme(name: "Dark", author: "GhostX")
    static let light = Theme(name: "Light", author: "GhostX",
        foreground: .init(red: 0, green: 0, blue: 0),
        background: .init(red: 1, green: 1, blue: 1),
        cursor: .init(red: 0, green: 0, blue: 0))
    static let solarizedDark = Theme(name: "Solarized Dark", author: "Ethan Schoonover",
        foreground: .init(red: 0.514, green: 0.58, blue: 0.588),
        background: .init(red: 0, green: 0.169, blue: 0.212),
        ansiBlack: .init(red: 0.027, green: 0.212, blue: 0.259),
        ansiRed: .init(red: 0.863, green: 0.196, blue: 0.184),
        ansiGreen: .init(red: 0.522, green: 0.6, blue: 0),
        ansiYellow: .init(red: 0.71, green: 0.537, blue: 0),
        ansiBlue: .init(red: 0.149, green: 0.545, blue: 0.824),
        ansiMagenta: .init(red: 0.827, green: 0.212, blue: 0.51),
        ansiCyan: .init(red: 0.165, green: 0.631, blue: 0.596),
        ansiWhite: .init(red: 0.933, green: 0.91, blue: 0.835))

    static let presets: [Theme] = [.dark, .light, .solarizedDark]

    struct HexColor: Codable, Hashable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double = 1.0
        var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
    }
}

/// Theme storage in UserDefaults
final class ThemeManager: ObservableObject {
    @Published var currentTheme: Theme = .dark
    @Published var customThemes: [Theme] = []

    private let defaults = UserDefaults.standard
    private let themesKey = "GhostX.themes"
    private let currentKey = "GhostX.currentTheme"

    init() { load() }

    func apply(_ theme: Theme) {
        currentTheme = theme
        defaults.set(theme.name, forKey: currentKey)
        // Notify all terminal views to redraw
        NotificationCenter.default.post(name: .init("GhostXThemeChanged"), object: theme)
    }

    func saveCustom(_ theme: Theme) {
        if let idx = customThemes.firstIndex(where: { $0.id == theme.id }) {
            customThemes[idx] = theme
        } else {
            customThemes.append(theme)
        }
        persist()
    }

    func deleteCustom(id: UUID) {
        customThemes.removeAll { $0.id == id }
        persist()
    }

    func allThemes() -> [Theme] { Theme.presets + customThemes }

    private func load() {
        if let data = defaults.data(forKey: themesKey),
           let themes = try? JSONDecoder().decode([Theme].self, from: data) {
            customThemes = themes
        }
        let savedName = defaults.string(forKey: currentKey) ?? "Dark"
        currentTheme = allThemes().first { $0.name == savedName } ?? .dark
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(customThemes) {
            defaults.set(data, forKey: themesKey)
        }
    }

    func exportTheme(_ theme: Theme, to url: URL) {
        if let data = try? JSONEncoder().encode(theme) {
            try? data.write(to: url)
        }
    }

    func importTheme(from url: URL) {
        if let data = try? Data(contentsOf: url),
           let theme = try? JSONDecoder().decode(Theme.self, from: data) {
            var t = theme; t.id = UUID()
            saveCustom(t)
        }
    }
}
