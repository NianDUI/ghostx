# GhostX — macOS 原生 Xshell 替代品

[English](README_en.md)

基于 Ghostty 终端引擎 + libssh2 的 macOS SSH 客户端，提供企业级远程服务器管理能力。

## 功能特性

### 终端仿真
- 完整 ANSI/SGR 解析：16 色 + 256 色 + TrueColor
- 粗体、斜体、下划线、闪烁、反转文字属性
- 可滚动回看（5000+ 行缓冲）
- 终端自适应大小、光标闪烁

### SSH 会话管理
- SQLite 持久化会话配置 + macOS Keychain 凭据存储
- 原生 libssh2 SSH 客户端（PTY 控制、resize、SFTP）
- 密码 + 公钥认证，支持浏览/生成 SSH 密钥
- 树形会话分组、JSON/CSV 导入导出
- SOCKS4/5/HTTP 代理、自动重连（最多 3 次）

### 多标签与分屏
- 多标签页管理，每个标签独立 SSH 连接
- 水平/垂直分屏视图
- 侧边栏可折叠、可调节宽度

### 批量操作
- 组合面板：向多个会话同时发送命令
- 快捷命令：保存/加载常用命令
- 多选或全选会话广播

### 文件传输
- SFTP 文件浏览器（libssh2 原生 + system sftp 回退）
- 远程文件列表、下载、上传
- 目录导航

### 隧道与转发
- 本地端口转发 (-L)、远程转发 (-R)、动态 SOCKS5 (-D)
- 隧道管理面板：添加/编辑/删除/预设模板

### 安全与自动化
- 会话日志（带时间戳，保存到文件）
- 触发器引擎：正则匹配终端输出 → 通知/命令/断开
- 右键上下文菜单（复制/粘贴/全选）、中键粘贴

### 外观
- 3 套预设主题 + 自定义主题编辑器 + 导入导出
- 主题感知 ANSI 调色板

## 构建与运行

```bash
# 安装依赖
brew install libssh2 zig

# 构建 libghostty-vt
cd reference/ghostty && zig build -Doptimize=ReleaseFast -p ../../build/ghostty

# 构建 GhostX
cd src && swift build

# 打包 .app
bash scripts/build_app.sh && open build/GhostX.app
```

## 系统要求
- macOS 14+ (Apple Silicon)
- Xcode 15+ / Swift 5.9
- libssh2 (Homebrew)

## 项目结构
```
src/GhostX/
├── Models/         # SessionConfig, Credential, TunnelConfig, Theme
├── Services/       # SSHClient, Libssh2Client, SessionRepository, etc.
├── Terminal/       # ANSIParser, TerminalBuffer, NativeTerminalView
├── Views/          # ContentView, SFTPPanel, TunnelManagerView, etc.
└── Utils/          # LocalizedString (中英文国际化)
```

## 开发
详见 `CLAUDE.md` 和 `EXECUTION_PLAN.md`。
