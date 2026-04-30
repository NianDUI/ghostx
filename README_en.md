# GhostX — macOS-native Xshell Alternative

[中文](README.md)

A macOS SSH client built on Ghostty terminal engine + libssh2, providing enterprise-grade remote server management.

## Features

### Terminal Emulation
- Full ANSI/SGR parsing: 16-color + 256-color + TrueColor
- Bold, italic, underline, blink, reverse video attributes
- Scrollback buffer (5000+ lines)
- Auto-resize, cursor blink

### SSH Session Management
- SQLite persistence + macOS Keychain credential storage
- Native libssh2 SSH client (PTY control, resize, SFTP)
- Password + public key auth, key browse/generate/import
- Tree-based session groups, JSON/CSV import/export
- SOCKS4/5/HTTP proxy, auto-reconnect (up to 3 attempts)

### Multi-tab & Split Panes
- Multi-tab management, independent SSH per tab
- Horizontal/vertical terminal splits
- Collapsible sidebar with adjustable width

### Batch Operations
- Compose panel: send commands to multiple sessions
- Quick commands: save/load frequently used commands
- Multi-select or broadcast-to-all

### File Transfer
- SFTP file browser (native libssh2 + system sftp fallback)
- Remote file listing, download, upload
- Directory navigation

### Tunnels & Forwarding
- Local (-L), remote (-R), dynamic SOCKS5 (-D) forwarding
- Tunnel manager panel: add/edit/delete/presets

### Security & Automation
- Session logging with timestamps (file output)
- Trigger engine: regex match → notify/command/disconnect
- Right-click context menu (Copy/Paste/Select All), middle-click paste

### Appearance
- 3 preset themes + custom theme editor + import/export
- Theme-aware ANSI color palette

## Build & Run

```bash
# Install dependencies
brew install libssh2 zig

# Build libghostty-vt
cd reference/ghostty && zig build -Doptimize=ReleaseFast -p ../../build/ghostty

# Build GhostX
cd src && swift build

# Package .app
bash scripts/build_app.sh && open build/GhostX.app
```

## Requirements
- macOS 14+ (Apple Silicon)
- Xcode 15+ / Swift 5.9
- libssh2 (Homebrew)

## Project Structure
```
src/GhostX/
├── Models/         # SessionConfig, Credential, TunnelConfig, Theme
├── Services/       # SSHClient, Libssh2Client, SessionRepository, etc.
├── Terminal/       # ANSIParser, TerminalBuffer, NativeTerminalView
├── Views/          # ContentView, SFTPPanel, TunnelManagerView, etc.
└── Utils/          # LocalizedString (zh/en i18n)
```

## Development
See `CLAUDE.md` and `EXECUTION_PLAN.md`.
