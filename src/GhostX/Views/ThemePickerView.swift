import SwiftUI

/// Theme switcher and color picker
struct ThemePickerView: View {
    @StateObject private var themeManager = ThemeManager()
    @State private var showEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terminal Theme")
                .font(.title3)

            Divider()

            // Preset + custom themes
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(themeManager.allThemes()) { theme in
                        themeSwatch(theme)
                    }
                }
            }

            Divider()

            // Actions
            HStack {
                Button("New Theme...") { showEditor = true }
                    .buttonStyle(.bordered)
                Button("Import...") { importTheme() }
                    .buttonStyle(.borderless)
                Spacer()
            }
        }
        .padding()
        .frame(width: 400, height: 350)
        .sheet(isPresented: $showEditor) {
            ThemeEditorView(themeManager: themeManager)
        }
    }

    private func themeSwatch(_ theme: Theme) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: NSColor(cgColor: theme.background.cgColor) ?? .black))
                    .frame(height: 50)
                    .overlay(
                        Text("Abc")
                            .font(.caption.monospaced())
                            .foregroundColor(Color(nsColor: NSColor(cgColor: theme.foreground.cgColor) ?? .white))
                    )
            }
            Text(theme.name)
                .font(.caption2)
                .lineLimit(1)
        }
        .padding(2)
        .background(themeManager.currentTheme.id == theme.id ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture { themeManager.apply(theme) }
        .contextMenu {
            Button("Set as Default") { themeManager.apply(theme) }
            if !Theme.presets.contains(where: { $0.id == theme.id }) {
                Button("Delete", role: .destructive) { themeManager.deleteCustom(id: theme.id) }
            }
        }
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        themeManager.importTheme(from: url)
    }
}

/// Color editor for creating/modifying themes
struct ThemeEditorView: View {
    @ObservedObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = "My Theme"
    @State private var fg = Color.white
    @State private var bg = Color.black
    @State private var cursor = Color.white

    var body: some View {
        VStack(spacing: 12) {
            Text("New Theme")
                .font(.title2)

            HStack {
                TextField("Theme Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Spacer()
            }

            // Preview
            HStack(spacing: 0) {
                ColorPicker("Foreground", selection: $fg)
                ColorPicker("Background", selection: $bg)
                ColorPicker("Cursor", selection: $cursor)
            }
            .padding()

            // Preview box
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(bg)
                    .frame(height: 60)
                Text("Hello, World!")
                    .font(.custom("JetBrainsMono-Regular", size: 13))
                    .foregroundColor(fg)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    let theme = Theme(
                        name: name, author: NSUserName(),
                        foreground: colorToHex(fg),
                        background: colorToHex(bg),
                        cursor: colorToHex(cursor)
                    )
                    themeManager.saveCustom(theme)
                    themeManager.apply(theme)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 320)
    }

    private func colorToHex(_ c: Color) -> Theme.HexColor {
        let ns = NSColor(c)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return .init(red: 0, green: 0, blue: 0) }
        return .init(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
    }
}
