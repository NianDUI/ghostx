# GhostX - Xshell-like SSH Client on Ghostty

## Project Overview

Build a macOS-native SSH client with Xshell-like session management, using **libghostty** for terminal rendering and **SwiftUI + AppKit** for the UI layer.

- **Target Platform**: macOS 14+ (Apple Silicon)
- **Language**: Swift 5.9+
- **License**: MIT
- **Reference**: https://www.xshell.com/zh/xshell-all-features/

---

## Architecture

```
┌─────────────────────────────────────────┐
│  UI Layer (SwiftUI + AppKit)             │
│  Sidebar │ TabBar │ ComposePanel │ SFTP   │
├─────────────────────────────────────────┤
│  Session Service Layer (Swift)           │
│  SessionRepository │ CredentialStore     │
│  SSHClient │ TabManager │ CommandBus     │
├─────────────────────────────────────────┤
│  Terminal Adapter Layer (Swift ↔ C FFI)  │
│  GhosttyTerminalView │ IOBridge           │
├─────────────────────────────────────────┤
│  SSH Transport (libssh2)                  │
│  Terminal Engine (libghostty)             │
└─────────────────────────────────────────┘
```

---

## Phase Plan

### Phase 0 — Prototype: Embed libghostty [ ]
**Goal**: SwiftUI app with embedded libghostty, local PTY works.
**Deliverables**:
- [ ] Xcode project with SwiftUI + AppKit mixed
- [ ] libghostty built as dynamic library (.dylib)
- [ ] GhosttyTerminalView (NSViewRepresentable wrapping libghostty surface)
- [ ] Local shell (zsh) running inside embedded terminal
- [ ] Window resize → cols/rows sync
**Files**: `GhosttyTerminalView.swift`, `TerminalSurface.swift`, `libghostty-bridge.h`

### Phase 1 — SSH Core [ ]
**Goal**: SSH connect with password & key auth, single session.
**Deliverables**:
- [ ] SSHClient class (libssh2 wrapper)
- [ ] Password + RSA/ED25519 key auth
- [ ] IOBridge: SSH channel ↔ libghostty stream
- [ ] Connect/disconnect lifecycle
- [ ] Keep-alive with configurable interval
- [ ] Terminal resize forwarded to SSH
**Files**: `SSHClient.swift`, `IOBridge.swift`, `AuthMethod.swift`

### Phase 2 — Session Persistence [ ]
**Goal**: Save/load sessions, multi-tab, credential storage.
**Deliverables**:
- [ ] Session config model (host/port/user/auth/options)
- [ ] SessionRepository (CRUD + SQLite)
- [ ] CredentialStore (Keychain for passwords/keys)
- [ ] TabManager (open/close/focus tabs)
- [ ] Multi-tab with independent sessions
- [ ] Quick connect bar
**Files**: `SessionConfig.swift`, `SessionRepository.swift`, `CredentialStore.swift`, `TabManager.swift`

### Phase 3 — Session Management [ ]
**Goal**: Session tree, groups, import/export.
**Deliverables**:
- [ ] Session tree sidebar (folders/groups)
- [ ] Drag & drop reorder
- [ ] JSON/CSV import & export
- [ ] Default session for quick connect
- [ ] Auto-login script per session
**Files**: `SessionTreeView.swift`, `SessionImportExport.swift`

### Phase 4 — Batch Operations [ ]
**Goal**: Send commands to multiple sessions simultaneously.
**Deliverables**:
- [ ] Compose panel (multi-line command input)
- [ ] Session multi-select for broadcasting
- [ ] CommandBus: dispatch to selected sessions
- [ ] Quick command collections (save & replay)
- [ ] Compose bar (single-line quick send)
**Files**: `ComposePanel.swift`, `CommandBus.swift`, `QuickCommandStore.swift`

### Phase 5 — Advanced Features [ ]
**Goal**: SFTP, tunnels, logging, themes.
**Deliverables**:
- [ ] SFTP file browser (list/upload/download/delete)
- [ ] Port forwarding manager (local/remote/dynamic)
- [ ] Session logging with timestamps
- [ ] Trigger engine (on output match → action)
- [ ] Theme editor (import/export color schemes)
- [ ] Custom layout (dockable panels)
**Files**: `SFTPBrowser.swift`, `TunnelManager.swift`, `SessionLogger.swift`, `TriggerEngine.swift`

---

## Key Module Interfaces

```swift
// Session Repository
protocol SessionRepository {
    func list() -> [SessionConfig]
    func get(id: UUID) -> SessionConfig?
    func save(_ config: SessionConfig) throws
    func delete(id: UUID) throws
    func move(id: UUID, toGroup: UUID?) throws
    func import_(url: URL) throws -> [SessionConfig]
    func export(ids: [UUID], to: URL) throws
}

// Credential Store
protocol CredentialStore {
    func savePassword(host: String, user: String, password: String) throws
    func saveKey(host: String, user: String, keyData: Data) throws
    func load(host: String, user: String) -> Credential?
    func delete(host: String, user: String) throws
}

// SSH Client
class SSHClient {
    func connect(host: String, port: UInt16, user: String, auth: AuthMethod) async throws
    func openShell(cols: Int, rows: Int) async throws -> SSHChannel
    func resize(cols: Int, rows: Int) throws
    func disconnect()
    var isConnected: Bool { get }
}

// Terminal Session
class TerminalSession {
    func attachIO(bridge: IOBridge)
    func write(_ data: Data)
    var onOutput: ((Data) -> Void)?
    var onExit: ((Int) -> Void)?
    var title: String { get set }
}

// Tab Manager
class TabManager: ObservableObject {
    func open(config: SessionConfig) -> UUID
    func close(id: UUID)
    func focus(id: UUID)
    func broadcast(command: String, to: [UUID])
    var tabs: [TerminalTab] { get }
}

// Command Bus
class CommandBus {
    func send(command: String, to sessions: [TerminalSession])
    func sendToAll(command: String)
    func registerQuickCommand(_ cmd: QuickCommand)
    func executeQuickCommand(id: UUID, targets: [UUID])
}
```

---

## libghostty Embedding Strategy

```
[SwiftUI View]
    └── GhosttyTerminalView: NSViewRepresentable
            └── GhosttySurfaceView: NSView
                    └── libghostty surface handle (ghostty_surface_t)
                            ├── Input callback → VT sequences → SSH write
                            ├── Render callback → Metal/GPU display
                            └── Resize callback → cols/rows → SSH window change
```

1. **Build libghostty** as `libghostty.dylib` from source (pin specific commit)
2. **Bridge header** declares C API functions imported from ghostty.h
3. **GhosttyTerminalView** wraps the NSView that hosts libghostty surface
4. **IOBridge** connects SSH channel stdout to libghostty input, and libghostty key events to SSH stdin
5. **Surface lifecycle**: create on tab open, destroy on tab close

---

## Reference Projects (auto-downloaded to reference/)

| Project | Path | Study Focus |
|---------|------|------------|
| ghostty | reference/ghostty/ | libghostty API, building, embedding |
| ghostling | reference/ghostling/ | Minimal libghostty embed example |
| tabby | reference/tabby/ | Plugin architecture, SessionManager pattern |
| nxshell | reference/nxshell/ | Broadcast command, ConnectionPool, EventBus |
| letsflutssh | reference/letsflutssh/ | Session tree storage, SQLCipher patterns |

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| libghostty API unstable | Pin known-good commit, abstract behind TerminalBackend protocol |
| SSH library issues | Protocol abstraction, fallback to libssh2 (most stable) |
| Scope creep | Strict P0→P5 ordering, each phase independently testable |
| Security: credential leak | Only Keychain for secrets, encrypted SQLite for config |
| Data corruption | Schema versioning, migration on app launch |

---

## Progress Tracking

- **Last updated**: 2026-04-30 22:00
- **Status**: Phase 0-5 ✅, Phase 6 60%, Phase 7-10 planned
- **Build**: 0.62s, zero warnings, .app 3.5MB
- **GitHub**: git@github.com:NianDUI/ghostx.git (8 commits)
- **Total files**: 42 source files + 4 docs + C bridge headers

### Phase Status
- Phase 0: COMPLETED ✅
- Phase 1: COMPLETED ✅
- Phase 2: COMPLETED ✅
- Phase 3: COMPLETED ✅
- Phase 4: COMPLETED ✅
- Phase 5: COMPLETED ✅ - Themes, key management, settings

### Files (28 total)
- Models (2): SessionConfig, Credential
- Services (6): SessionRepository, CredentialStore, SSHClient, SessionLogger, TriggerEngine, SFTPService
- Terminal (5): ANSIParser, TerminalBuffer, NativeTerminalView, TerminalBridge, ghostty_bridge.c
- Views (8): ContentView, TerminalViews, NewSessionSheet, SFTPPanel, TriggerConfigView, GhostXApp
- Other (7): Package.swift, build_app.sh, bridging headers, dylib, reference repos

### Recently Completed
- [x] ANSIParser - streaming ANSI escape sequence parser (CSI, SGR, OSC, DEC)
- [x] TerminalBuffer - 2D cell grid with scrollback, ANSI state tracking
- [x] NativeTerminalView - AppKit NSView with CoreText rendering
- [x] TerminalDisplay - SwiftUI wrapper for NativeTerminalView
- [x] TerminalView updated to use native rendering (colors, bold, italic, etc.)
- [x] Scrollback viewing with mouse wheel
- [x] Cursor rendering with blink timer
- [x] 256-color + TrueColor support

### Completed Items
- [x] Project architecture design (Claude + Codex discussion)
- [x] Reference projects downloaded (ghostty, ghostling, tabby, nxshell, letsflutssh)
- [x] libghostty-vt built (dylib + static lib)
- [x] Data models: SessionConfig, Credential, QuickCommand, SessionLogEntry, Trigger
- [x] SessionRepository (SQLite CRUD + import/export)
- [x] CredentialStore (macOS Keychain wrapper)
- [x] SSHClient (Process-based SSH with PTY)
- [x] TerminalBridge (libghostty-vt wrapper stub)
- [x] ContentView (sidebar + terminal + compose panel layout)
- [x] TerminalArea + TabManager (multi-tab management)
- [x] QuickConnectBar + SessionTree
- [x] NewSessionSheet (config form)
- [x] ComposePanel (batch command with multi-select)
- [x] GhostXApp entry point + Settings
- [ ] Swift package compilation passing
- [ ] Xcode project creation
- [ ] App bundle generation
- [ ] Integration testing

### Files Created (15 files)
- `src/GhostX/Models/SessionConfig.swift`
- `src/GhostX/Models/Credential.swift`
- `src/GhostX/Services/SessionRepository.swift`
- `src/GhostX/Services/CredentialStore.swift`
- `src/GhostX/Services/SSHClient.swift`
- `src/GhostX/Terminal/TerminalBridge.swift`
- `src/GhostX/Views/ContentView.swift` (includes SessionSidebar, SessionRow, QuickConnectBar)
- `src/GhostX/Views/TerminalViews.swift` (includes TabManager, TerminalArea, TabButton, TerminalView, ComposePanel)
- `src/GhostX/Views/NewSessionSheet.swift`
- `src/GhostX/GhostXApp.swift` (includes SettingsView)
- `src/Package.swift`
- `reference/` (5 cloned repos)
- `build/ghostty/` (libghostty-vt dylib)
- `design/` (architecture docs)
- `logs/` (session logs)

---

## Phase 6-10: Xshell Parity Plan (2026-04-30)

Based on joint analysis by Claude + Codex-unsafe of:
- https://www.xshell.com/zh/xshell-all-features/
- https://www.xshell.com/zh/xshell/
- Web research on Xshell UI/UX patterns
- Current GhostX gap analysis

### Gap Analysis (Top 5)

| # | Gap | Xshell | GhostX Current |
|---|-----|--------|----------------|
| 1 | **Dockable Workspace** | MDI with dockable panels, split panes, tab groups, auto-hide | Fixed HSplitView, no splits, no drag-reorder |
| 2 | **Session Center 2.0** | Fuzzy search, tag labels, bulk CSV/XML import-export, auth profiles | Basic tree, JSON import only |
| 3 | **SFTP Dual-Pane** | Docked bottom panel, local+remote side-by-side, drag-drop, transfer queue | Popover single-pane browser |
| 4 | **Terminal Pro Features** | Horizontal scroll, column/block selection, >100K scrollback, hex viewer | Vertical scroll only, 5000 line buffer |
| 5 | **Security & Extensions** | PKCS#11/GSSAPI/Kerberos, script recording, master password, auth profile propagation | Basic key+password, no Kerberos |

### New Phases

### Phase 6 — Dockable Workspace [IN_PROGRESS 60%]
**Priority**: P0 (highest UI impact)
- [x] Terminal split panes (SplitManager + SplitTreeView, recursive tree)
- [x] Collapsible sidebar with toggle button
- [x] Right-click context menu (Copy/Paste/Select All)
- [x] Middle-click paste support
- [x] Sidebar width adjustable
- [ ] Panel dock/undock (bottom SFTP, right quick commands as dockable)
- [ ] Panel auto-hide with hover reveal
- [ ] Tab drag-to-reorder, drag-to-split
- [ ] Layout state persistence (UserDefaults — save split tree)
- [ ] Session icon customization

### Phase 7 — Session Center 2.0 [IN_PROGRESS 70%]
- [x] Session tags field in model (SessionConfig.tags)
- [x] Session usage stats (lastConnectedAt, connectCount)
- [x] Fuzzy search in session list (filter by name/host/user/tags)
- [x] Colored tag chips display in session rows
- [ ] Bulk edit (select multiple sessions, change common properties)
- [ ] CSV + JSON import/export with file picker (JSON done, CSV partial)
- [ ] Auth profiles (reusable credential configurations)

### Phase 8 — SFTP Dual-Pane [ ]
- [ ] Bottom-docked SFTP panel (local left + remote right split)
- [ ] Drag-drop file upload from Finder to remote
- [ ] Download with progress indicator + cancel
- [ ] Transfer queue (multiple files, sequential/parallel)
- [ ] File conflict resolution dialog (overwrite/skip/rename)
- [ ] Inline text preview for remote files
- [ ] Hex viewer for binary files

### Phase 9 — Terminal Professional [ ]
- [ ] Horizontal scrollbar when content exceeds terminal width
- [ ] Column/block text selection (Alt+Mouse drag)
- [ ] Increase scrollback buffer to 100K lines
- [ ] Triple-click selects entire line
- [ ] Customizable double-click word separators
- [ ] Terminal print (save visible content as PDF)
- [ ] Mouse right-button action config (menu/paste/send)

### Phase 10 — Advanced Protocols & Security [ ]
- [ ] TELNET protocol support (libtelnet or custom)
- [ ] RDP session launcher (open via system RDP client)
- [ ] PKCS#11 smart card auth
- [ ] GSSAPI/Kerberos authentication
- [ ] Master password to encrypt all stored credentials
- [ ] Script recording (record input → replay)

---

### Change Log
- 2026-04-30 16:00: Initial plan created based on Claude + Codex discussion
- 2026-04-30 21:40: Xshell parity analysis — Claude + Codex-unsafe joint research
- 2026-04-30 21:45: Phase 6-10 plan added covering dockable UI, session center, SFTP dual-pane, terminal pro, advanced protocols
