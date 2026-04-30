# GhostX 基于 Ghostty 的执行计划

## Progress

- [ ] Phase 0: 基线冻结与对齐
- [ ] Phase 1: 引入 Ghostty 终端基座
- [ ] Phase 2: 替换当前终端渲染主路径
- [ ] Phase 3: Ghostty 风格 UI 重构
- [ ] Phase 4: 输入、选择、滚动与高级终端行为补齐
- [ ] Phase 5: 业务模块适配和回归
- [ ] Phase 6: 清理旧实现

## 目标

以 `/Users/lyd/WorkSpace/Ai/ghostty` 提供的 `libghostty-vt` 能力为终端内核，保留 `ghostx` 现有的 SSH、SFTP、会话管理和多窗口业务层，逐步替换当前自绘终端实现，使产品在技术栈和页面观感上同时向 Ghostty 对齐。

这不是把 `ghostx` 直接改造成 `ghostty` app，也不是把 `ghostty` 大仓库搬进来重写，而是：

- 终端内核和输入编码基于 `ghostty`
- macOS 页面展示风格基于 `ghostty`
- 会话、协议、文件传输、批量操作继续以 `ghostx` 为主体

## 当前判断

当前仓库状态：

- `ghostx` 已有 `ghostty` 头文件、C bridge 和动态库加载桥接
- 但终端主路径仍是 `TerminalBuffer + ANSIParser + NativeTerminalView`
- `TerminalBridge.readScreenCells()` 尚未实现
- `plan/EXECUTION_PLAN.md` 与当前代码现实不完全一致，不能直接作为实施依据

结论：

- 可行方向是“以 `ghostty` 的 `libghostty-vt` 为基础重构终端层”
- 不建议“以完整 `ghostty` 应用工程为基础重写 GhostX”

## 产品原则

### 技术原则

- `ghostty` 负责终端状态机、VT 解析、输入编码
- `ghostx` 负责连接、会话、存储、SFTP、广播、业务 UI
- 先替换终端核心，再处理外围高级功能
- 每个阶段都必须保持可编译、可运行、可回退

### 页面风格原则

页面展示风格使用 `ghostty` 的 macOS 视觉语言，不使用当前仓库里偏业务工具化、偏表单堆叠的风格。

明确约束如下：

- 以 terminal surface 为视觉中心，其他面板是辅助，不反客为主
- 优先原生 macOS 材质：`NSVisualEffectView`、`regularMaterial`、系统分隔线、系统背景色
- 控件密度偏紧凑，避免大面积空洞卡片和过多边框
- 分屏边界使用 1px 式细分隔线，交互热区可以大，但视觉线条必须克制
- 焦点态明显，非焦点 split/surface 允许轻微 dim
- 颜色以终端主题为主，外层 UI 只做弱强调，不做高饱和大面积装饰
- 工具栏、侧边栏、tab 区采用原生语义，避免 Web 化 UI
- 动效只保留必要状态反馈：focus、hover、resize、overlay，禁止泛滥转场

## 总体实施路径

### Phase 0: 基线冻结与对齐

目标：

- 确认当前 `ghostx` 可构建状态
- 明确哪些模块保留，哪些模块将被替换
- 补一份新计划作为唯一执行基线

任务：

- 记录当前终端渲染链路和依赖关系
- 标记所有直接依赖 `TerminalBuffer` / `ANSIParser` / `NativeTerminalView` 的代码
- 明确桥接层是否走 `dylib` 还是 `xcframework`
- 在 `plan/` 下维护本计划和后续进度日志

交付：

- 本计划文档
- 一份终端模块依赖清单

验收：

- 团队对技术路径和视觉方向没有歧义

### Phase 1: 引入 Ghostty 终端基座

目标：

- 让 `ghostx` 真正使用 `/Users/lyd/WorkSpace/Ai/ghostty` 产出的 `libghostty-vt`
- 打通最小读写闭环

任务：

- 选择接入方式
- 优先方案：使用 `ghostty-vt.xcframework`
- 备选方案：继续通过 `libghostty-vt.dylib + dlopen`
- 清理和统一当前 `ghostty_include`、bridge header、C bridge 的组织方式
- 补齐 `TerminalBridge`
- 实现 terminal create/free/resize/write
- 实现 render state 行列读取
- 实现 title change 和 write-to-pty 回调
- 建立 `GhosttyTerminalSession` 之类的单一抽象，隔离 Swift UI 与 C bridge

交付：

- 可初始化的 `libghostty-vt` 终端实例
- 可以写入 VT 数据并读回 screen cells

验收：

- 本地 shell 或 mock 数据能正确显示
- resize 后行列同步
- 标题、普通文本、颜色、光标基础行为正常

### Phase 2: 替换当前终端渲染主路径

目标：

- 用新的 Ghostty 终端视图替换 `NativeTerminalView`
- 保持 `ghostx` 现有 SSH/TELNET 连接模型可继续工作

任务：

- 新增 `GhosttyTerminalView`
- 由 SwiftUI/AppKit 承载终端 surface
- 先走 screen cells 绘制方案，保持接入成本可控
- 之后再评估是否进一步接完整 surface 渲染能力
- 将 `SSHClient.onOutput` 改为直接喂给 `TerminalBridge`
- 将键盘输入从“直接发字符”升级为“经 Ghostty key encoder 输出”
- 保留现有终端 view 作为临时 fallback

交付：

- SSH 会话真实走 `libghostty-vt`
- 新 terminal view 成为默认路径

验收：

- 连接远程主机后能正确执行交互式 shell
- 常见按键可用：回车、退格、方向键、PageUp/PageDown、Home/End、Tab
- 终端滚动和选择行为不退化到不可用状态

### Phase 3: Ghostty 风格 UI 重构

目标：

- 页面展示风格向 Ghostty 靠齐
- 不改变 `ghostx` 的业务布局能力，但统一视觉语言

任务：

- 提取 `GhosttyStyle` 主题层
- 定义窗口背景、侧边栏材质、split divider、toolbar、tab 状态、focus overlay
- 改造主界面
- `ContentView`
- `TerminalViews`
- `SplitManager`
- `ThemePickerView`
- `NewSessionSheet`
- 侧边栏改为原生语义：弱边框、弱阴影、系统材质、紧凑层级
- tab bar 改为 Ghostty 风格：轻量标签、弱色块焦点、高信息密度
- split pane 使用细分隔线和清晰 focus 态
- overlay 统一：连接中、错误、只读、通知、搜索、resize 提示

交付：

- 一套统一的 Ghostty 风格 macOS 界面

验收：

- UI 视觉中心始终是 terminal
- 侧栏、tab、split、toolbar 风格一致
- 不出现明显 Web 化组件感

### Phase 4: 输入、选择、滚动与高级终端行为补齐

目标：

- 把当前自绘终端具备但 Ghostty 新链路尚缺的交互能力补齐

任务：

- 鼠标选择、双击、三击、列选择
- 滚动回看和大缓冲读取
- 剪贴板复制粘贴
- URL hover / open
- 光标样式与闪烁控制
- 搜索 overlay
- 焦点切换和 split 间输入状态同步

交付：

- 可日常使用的 terminal interaction 层

验收：

- 常见 shell 使用场景无明显退化
- `vim` / `less` / `top` / `ssh` 嵌套等基础场景可接受

### Phase 5: 业务模块适配和回归

目标：

- 确保 Ghostty 新终端层与现有高级功能兼容

任务：

- 检查并适配：
- 日志记录
- TriggerEngine
- ScriptRecorder
- 批量广播
- 分屏布局持久化
- SFTP 面板联动
- Xshell 导入后的会话打开流程
- TELNET 和 fallback SSH 路径

交付：

- 业务功能在新终端层下稳定工作

验收：

- 现有核心功能不因终端重构失效

### Phase 6: 清理旧实现

目标：

- 清理不再需要的旧终端实现，降低维护成本

任务：

- 删除或降级旧的 `ANSIParser`、`TerminalBuffer`、`NativeTerminalView` 路径
- 移除重复的输入映射逻辑
- 更新 README、构建脚本、依赖说明
- 更新 `plan/EXECUTION_PLAN.md`，避免文档继续失真

交付：

- 单一终端主路径
- 干净的构建与文档

验收：

- 代码中不存在两套长期并行的主终端实现

## 界面改造范围

优先改造页面：

- `src/GhostX/Views/ContentView.swift`
- `src/GhostX/Views/TerminalViews.swift`
- `src/GhostX/Views/SplitManager.swift`
- `src/GhostX/Views/NewSessionSheet.swift`
- `src/GhostX/Views/ThemePickerView.swift`
- `src/GhostX/Views/SFTPPanel.swift`

新增建议：

- `src/GhostX/Views/Style/GhosttyStyle.swift`
- `src/GhostX/Views/Style/GhosttyMaterials.swift`
- `src/GhostX/Terminal/GhosttyTerminalView.swift`
- `src/GhostX/Terminal/GhosttyTerminalSession.swift`

## 关键技术决策

### 决策 1: 不以完整 Ghostty app 为基座重写

原因：

- `ghostty` app 体量太大
- 其窗口、surface、配置、菜单、运行时体系与 `ghostx` 业务目标不一致
- 改造成本远高于复用 `libghostty-vt`

### 决策 2: 优先采用 libghostty-vt，不直接绑定完整 libghostty surface 体系

原因：

- 当前仓库已经有 vt bridge
- 接入面更小，适合渐进替换
- 能更好保留 `ghostx` 自己的会话和多协议层

### 决策 3: 页面风格模仿 Ghostty，不照搬其完整信息架构

原因：

- `ghostty` 是 terminal app
- `ghostx` 是 session-centric SSH client
- 两者视觉语言可以统一，但信息结构不能硬套

## 风险与应对

### 风险 1: libghostty-vt 接入后功能短期倒退

应对：

- 保留旧 terminal view 作为阶段性 fallback
- 分阶段切默认开关

### 风险 2: `ghostty` 上游 API 变化

应对：

- 固定本地依赖路径和 commit
- bridge 层只暴露最小必要接口

### 风险 3: 页面改造过度追求像 Ghostty，削弱 SSH 管理效率

应对：

- 风格对齐，不抄结构
- 所有 UI 以“会话效率优先”为最终标准

## 构建与依赖建议

- 将 `/Users/lyd/WorkSpace/Ai/ghostty` 固定为本地开发依赖来源
- 产物建议优先统一为：
- `ghostty-vt.xcframework`
- 或固定位置的 `libghostty-vt.dylib`
- 在 `scripts/` 中新增统一构建脚本：
- 构建 ghostty vt
- 复制产物到 `ghostx` 可消费目录
- 再构建 `ghostx`

## 里程碑

### M1

- Ghostty 终端实例可创建、写入、读取、resize

### M2

- SSH 真实跑在新终端层上

### M3

- 主页面完成 Ghostty 风格改造

### M4

- 高级交互补齐

### M5

- 旧终端路径清理完成

## 建议执行顺序

1. 先做终端内核接入，不先做外观翻新
2. 新终端链路可跑后，再统一 UI 风格
3. 高级功能在新主路径稳定后再回归
4. 最后清理旧实现和更新文档

## 下一步

下一阶段应直接开始 Phase 1，先完成：

- 统一 `ghostty` 依赖接入方式
- 补齐 `TerminalBridge.readScreenCells()`
- 新建 `GhosttyTerminalView`
- 让单个 SSH session 先跑通
