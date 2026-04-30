import Foundation

/// Simple i18n string lookup with language preference support.
enum L10n {
    /// Language preference: "zh", "en", or nil (system default)
    static var preferredLanguage: String? {
        get { UserDefaults.standard.string(forKey: "GhostX.language") }
        set { UserDefaults.standard.set(newValue, forKey: "GhostX.language") }
    }
    private static var isZh: Bool {
        if let pref = preferredLanguage { return pref == "zh" }
        return Locale.current.language.languageCode?.identifier == "zh"
    }

    // MARK: - App
    static var appName: String { "GhostX" }

    // MARK: - Menu & Commands
    static var newSession: String { isZh ? "新建会话..." : "New Session..." }
    static var quickConnect: String { isZh ? "快速连接..." : "Quick Connect..." }
    static var broadcastToAll: String { isZh ? "广播到所有..." : "Broadcast to All..." }

    // MARK: - Session
    static var sessions: String { isZh ? "会话" : "Sessions" }
    static var sessionName: String { isZh ? "会话名称" : "Session Name" }
    static var host: String { isZh ? "主机" : "Host" }
    static var port: String { isZh ? "端口" : "Port" }
    static var username: String { isZh ? "用户名" : "Username" }
    static var authMethod: String { isZh ? "认证方式" : "Auth Method" }
    static var password: String { isZh ? "密码" : "Password" }
    static var privateKey: String { isZh ? "私钥" : "Private Key" }
    static var key: String { isZh ? "密钥" : "Key" }
    static var agent: String { isZh ? "代理" : "Agent" }
    static var loginScript: String { isZh ? "登录脚本" : "Login Script" }
    static var connectAfterSave: String { isZh ? "保存后连接" : "Connect after saving" }
    static var noSessionsOpen: String { isZh ? "未打开会话" : "No sessions open" }
    static var doubleClickToConnect: String { isZh ? "双击侧栏会话或使用快速连接" : "Double-click a session in the sidebar or use Quick Connect" }
    static var connect: String { isZh ? "连接" : "Connect" }
    static var disconnect: String { isZh ? "断开" : "Disconnect" }
    static var connected: String { isZh ? "已连接" : "Connected" }
    static var disconnected: String { isZh ? "已断开" : "Disconnected" }

    // MARK: - Terminal
    static var terminal: String { isZh ? "终端" : "Terminal" }
    static var terminalType: String { isZh ? "终端类型" : "Terminal Type" }
    static var keepAlive: String { isZh ? "心跳间隔 (秒)" : "Keep Alive (s)" }
    static var fontSize: String { isZh ? "字体大小" : "Font Size" }
    static var copy: String { isZh ? "复制" : "Copy" }
    static var paste: String { isZh ? "粘贴" : "Paste" }
    static var selectAll: String { isZh ? "全选" : "Select All" }

    // MARK: - SFTP
    static var sftpBrowser: String { isZh ? "SFTP 文件浏览器" : "SFTP File Browser" }
    static var upload: String { isZh ? "上传" : "Upload" }
    static var download: String { isZh ? "下载" : "Download" }
    static var refresh: String { isZh ? "刷新" : "Refresh" }
    static var path: String { isZh ? "路径" : "Path" }
    static var name: String { isZh ? "名称" : "Name" }
    static var size: String { isZh ? "大小" : "Size" }
    static var date: String { isZh ? "日期" : "Date" }
    static var noFiles: String { isZh ? "无文件" : "No files" }

    // MARK: - Batch Commands
    static var batchCommand: String { isZh ? "批量命令" : "Batch Command" }
    static var selectedCount: String { isZh ? "已选" : "selected" }
    static var sendToSelected: String { isZh ? "发送到选中" : "Send to Selected" }
    static var sendToAll: String { isZh ? "发送到全部" : "Send to All" }
    static var quickCommands: String { isZh ? "快捷命令" : "Quick Commands" }
    static var saveQuickCommand: String { isZh ? "保存快捷命令..." : "Save Quick Cmd..." }
    static var cmdName: String { isZh ? "命令名称" : "Cmd name" }

    // MARK: - Tunnels
    static var tunnels: String { isZh ? "端口转发与隧道" : "Port Forwarding & Tunnels" }
    static var noTunnels: String { isZh ? "未配置隧道" : "No tunnels configured" }
    static var addTunnel: String { isZh ? "添加隧道" : "Add Tunnel" }
    static var tunnelDetail: String { isZh ? "添加隧道转发本地和远程端口" : "Add a tunnel to forward ports between local and remote hosts." }

    // MARK: - Triggers
    static var triggers: String { isZh ? "触发器" : "Triggers" }
    static var triggerConfig: String { isZh ? "触发器配置" : "Trigger Configuration" }

    // MARK: - Themes
    static var themes: String { isZh ? "终端主题" : "Terminal Themes" }
    static var newTheme: String { isZh ? "新建主题..." : "New Theme..." }
    static var importTheme: String { isZh ? "导入..." : "Import..." }
    static var foreground: String { isZh ? "前景色" : "Foreground" }
    static var background: String { isZh ? "背景色" : "Background" }
    static var cursor: String { isZh ? "光标" : "Cursor" }

    // MARK: - Settings
    static var settings: String { isZh ? "设置" : "Settings" }
    static var general: String { isZh ? "通用" : "General" }
    static var appearance: String { isZh ? "外观" : "Appearance" }
    static var sshKeys: String { isZh ? "SSH 密钥" : "SSH Keys" }
    static var proxySettings: String { isZh ? "代理设置" : "Proxy Settings" }
    static var enableProxy: String { isZh ? "启用代理" : "Enable Proxy" }
    static var proxyType: String { isZh ? "代理类型" : "Proxy Type" }
    static var proxyHost: String { isZh ? "代理主机" : "Proxy Host" }

    // MARK: - Actions
    static var save: String { isZh ? "保存" : "Save" }
    static var cancel: String { isZh ? "取消" : "Cancel" }
    static var delete: String { isZh ? "删除" : "Delete" }
    static var edit: String { isZh ? "编辑" : "Edit" }
    static var close: String { isZh ? "关闭" : "Close" }
    static var browse: String { isZh ? "浏览" : "Browse" }
    static var generate: String { isZh ? "生成" : "Generate" }
    static var `import`: String { isZh ? "导入" : "Import" }
    static var export: String { isZh ? "导出" : "Export" }
    static var splitH: String { isZh ? "水平分屏" : "Split Horizontal" }
    static var splitV: String { isZh ? "垂直分屏" : "Split Vertical" }
    static var toggleCompose: String { isZh ? "切换组合面板" : "Toggle Compose Panel" }

    // MARK: - Password Prompt
    static var sshAuth: String { isZh ? "SSH 认证" : "SSH Authentication" }
    static var enterPassword: String { isZh ? "输入密码" : "Enter password" }
    static var saveToKeychain: String { isZh ? "保存到钥匙串" : "Save to Keychain" }
    static var passwordRequired: String { isZh ? "需要密码" : "Password required" }
    static var noCredentials: String { isZh ? "无可用凭据" : "No credentials" }
}
