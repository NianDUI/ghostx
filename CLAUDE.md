# CLAUDE.md — GhostX Project Guide

## Project Overview
GhostX is a macOS-native SSH client with Xshell-like session management, built on Ghostty terminal engine + libssh2. It provides enterprise-grade remote server management with multi-tab terminals, batch command execution, SFTP file browsing, and port forwarding.

## Build & Run
```bash
# Build the Swift package
cd src && swift build

# Build the .app bundle
bash scripts/build_app.sh

# Run
open build/GhostX.app
```

## Architecture
```
src/GhostX/
├── Models/         # Data models: SessionConfig, Credential, TunnelConfig, Theme
├── Services/       # Business logic: SSHClient, Libssh2Client, SessionRepository, etc.
├── Terminal/       # Terminal engine: ANSIParser, TerminalBuffer, NativeTerminalView
├── Views/          # SwiftUI views: ContentView, TerminalViews, SFTPPanel, etc.
└── Utils/          # Utilities: LocalizedString (i18n)
src/GhostXBridge/   # C bridge layer: libghostty-vt + libssh2 wrappers
```

## Key Design Decisions
- **Terminal rendering**: Custom CoreText NSView (NativeTerminalView) + TerminalBuffer grid
- **SSH**: Libssh2Client (native via dlopen) with SSHClient fallback (Process-based ssh)
- **Storage**: SQLite for sessions, macOS Keychain for credentials
- **i18n**: L10n enum in Utils/LocalizedString.swift — add strings there for both zh/en

## Adding Features
1. New service → `Services/`
2. New UI view → `Views/`
3. New model → `Models/`
4. Update i18n strings → `Utils/LocalizedString.swift`
5. Run `swift build` to verify, `bash scripts/build_app.sh` to package
6. Commit to `main`, push to `git@github.com:NianDUI/ghostx.git`

## Dependencies
- macOS 14+, Xcode 15+, Swift 5.9
- libssh2 (Homebrew: `brew install libssh2`)
- libghostty-vt (built from source: `zig build -Doptimize=ReleaseFast`)
