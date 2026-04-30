import SwiftUI

/// Hex viewer for binary data — shows hex + ASCII side by side
struct HexViewer: View {
    let data: Data
    @State private var offset: Int = 0
    private let bytesPerRow = 16

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("Offset  ").frame(width: 90, alignment: .leading)
                ForEach(0..<bytesPerRow, id: \.self) { i in
                    Text(String(format: "%02X", i))
                        .frame(width: 28, alignment: .center)
                }
                Text("  ASCII").frame(width: 140, alignment: .leading)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            Divider()

            // Hex rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    let maxOffset = min(offset + 100 * bytesPerRow, data.count)
                    let startRow = (offset / bytesPerRow) * bytesPerRow

                    ForEach(Array(stride(from: startRow, to: maxOffset, by: bytesPerRow)), id: \.self) { rowOffset in
                        HStack(spacing: 0) {
                            // Offset
                            Text(String(format: "%08X", rowOffset))
                                .foregroundColor(.blue)
                                .frame(width: 90, alignment: .leading)

                            // Hex bytes
                            ForEach(0..<bytesPerRow, id: \.self) { i in
                                let idx = rowOffset + i
                                if idx < data.count {
                                    Text(String(format: "%02X", data[idx]))
                                        .frame(width: 28, alignment: .center)
                                } else {
                                    Text("  ").frame(width: 28, alignment: .center)
                                }
                            }

                            // ASCII representation
                            Text("  ").frame(width: 4)
                            ForEach(0..<bytesPerRow, id: \.self) { i in
                                let idx = rowOffset + i
                                if idx < data.count {
                                    let byte = data[idx]
                                    let ch = (byte >= 32 && byte < 127) ? String(UnicodeScalar(byte)) : "."
                                    Text(ch).frame(width: 8, alignment: .center)
                                }
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 4)
                    }
                }
            }

            Divider()

            // Navigation
            HStack {
                Button("Top") { offset = 0 }
                    .disabled(offset == 0)
                Button("Prev") {
                    offset = max(0, offset - 256 * bytesPerRow)
                }
                Button("Next") {
                    offset = min(data.count - bytesPerRow, offset + 256 * bytesPerRow)
                }
                    .disabled(offset >= data.count - bytesPerRow)
                Spacer()
                Text("\(formatBytes(data.count)) total")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(4)
        }
        .frame(minWidth: 600, minHeight: 300)
    }

    private func formatBytes(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1048576 { return String(format: "%.1f KB", Double(n)/1024) }
        return String(format: "%.1f MB", Double(n)/1048576)
    }
}

/// Simple hex viewer for a file at a given URL
struct FileHexViewer: View {
    let url: URL
    @State private var data: Data?
    @State private var error: String?

    var body: some View {
        Group {
            if let data = data {
                HexViewer(data: data)
            } else if let error = error {
                Text("Error: \(error)").foregroundColor(.red).padding()
            } else {
                ProgressView("Loading...").padding()
            }
        }
        .onAppear {
            do {
                data = try Data(contentsOf: url)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
