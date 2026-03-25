# FlowTabApp

FlowTabApp 是一个 macOS 应用切换器项目。目标是在接近系统 `Command + Tab` 手感的前提下，提供更可控的多窗口切换能力，并支持窗口预览与运行时诊断。

本 README 是当前唯一维护的需求与实现总览文档。  
`FlowTabCore/docs/requirements.md` 与 `FlowTabCore/docs/implementation-split.md` 仅保留跳转说明。

## 仓库结构

- `FlowTabApp/`：macOS 应用层（热键、切换面板、运行时桥接、首页与监控 UI）
- `FlowTabCore/`：核心状态机与模型（可单测）
- `FlowTabAppTests/`、`FlowTabAppUITests/`：应用测试
- `scripts/`：打包安装脚本（固定路径 Release 安装）
- `docs/`：工程注意事项

## 当前需求基线（2026-03-25）

### 1) 主切换与结束快捷键

- 默认主切换：
  - 正向：`Option + Tab`
  - 反向：`Option + Shift + Tab`
- 结束应用：
  - 目标行为：`Option + Q`（语义对齐系统 `Command + Q`，结束当前高亮应用）
- 快捷键自定义：
  - 目标行为：主切换与结束应用均支持自定义

### 2) 层级与窗口层触发规则

- 初始在应用层切换。
- 当前高亮应用窗口数 `>= 2` 时，自动进入窗口层。
- 自动进入窗口层采用延迟展示（当前实现延迟约 `0.22s`），避免快速扫过时被打断。
- 在应用层可通过 `↓` 手动进入窗口层（仅当窗口数 `>= 2`）。
- 在窗口层按 `↑` 返回应用层。
- 若从窗口层按 `↑` 返回应用层，则当前应用在本次面板会话内不再自动进入窗口层；需要按 `↓` 才能再次进入窗口层。
- 当高亮切换到其他应用（`Option + Tab` / `Option + Shift + Tab` / `←` / `→`）时，上述“当前应用临时抑制”立即失效。
- 核心规则固定：只有窗口数 `>= 2` 才允许进入窗口层。

### 3) 确认与激活语义

- 在应用层确认：应激活应用。
- 在窗口层确认：应激活窗口。
- 不应在应用层确认时隐式下钻到窗口。

### 4) 数据一致性

- UI 展示窗口数与切换逻辑必须使用同一套数据。
- 当前策略：窗口计数与窗口候选统一使用 AX（Accessibility）窗口列表。
- CGWindow 仅用于窗口预览映射，不参与窗口数判定。

### 5) 窗口预览

- 进入窗口层后，面板展示当前选中窗口预览图。
- 预览抓图链路：优先使用已映射 `CGWindowID`，失败时按 `pid + window title` 实时重查候选窗口并重试。
- 预览抓取失败时，回退为渐变背景 + 应用图标（不中断切换流程）。

### 6) 可见性与调试体验

- 运行应用后有可见首页窗口，便于确认“已启动”。
- 首页包含 Tab：`首页` / `监控页面` / `预览日志`。
- 监控页面可查看运行日志、手动采集快照、请求辅助功能与屏幕录制权限、清空日志。
- 预览日志 Tab 仅展示 `Preview` 分类日志，用于排查窗口预览权限/窗口匹配/抓图失败。

## 模块分工（实现拆分）

### Core（FlowTabCore）

1. `Preferences`
- 热键模型、窗口切换策略、导航开关、主题等偏好。

2. `Grouping`
- 应用分组构建与索引映射。

3. `SwitcherSession`
- 切换状态机（应用层 / 分组层 / 窗口层）与确认目标决策。

4. `FlowTabCoreTests`
- 状态机关键路径回归测试。

### App（FlowTabApp）

1. `OptionTabHotkeyMonitor`
- 全局热键注册与分发（当前为 `Option + Tab` / `Option + Shift + Tab`）。

2. `SwitcherPanelController` + `LiveSwitcherModel`
- 面板展示、按键处理、延迟自动进入窗口层、提交/取消、窗口预览展示。

3. `RuntimeSnapshotProvider` + `RuntimeActivator`
- 运行时应用/窗口快照与激活动作执行。
- AX 窗口作为窗口层单一数据源。
- 通过 AX->CGWindowID 映射为窗口预览提供目标窗口 ID。

4. `RuntimeWindowPreviewProvider`
- 基于 `CGWindowListCreateImage` 抓取窗口预览（需屏幕录制权限）。

5. `FlowTabAppApp`
- 应用生命周期、首页 Tab UI、状态栏菜单、运行日志监控页、预览日志页。

## 实现状态（需求对照）

| 需求项 | 状态 | 说明 |
| --- | --- | --- |
| Option+Tab / Option+Shift+Tab 主切换 | 已实现 | 全局热键监听已接入 |
| 窗口数 `>=2` 自动进入窗口层 + 延迟展示 | 已实现 | 默认自动进入；若从窗口层 `↑` 返回，则当前应用在本次会话内临时抑制自动进入 |
| 窗口层 `↑` 返回应用层 + `↓` 手动重新进入 | 已实现 | `↑` 返回后需按 `↓` 才能重新进入；切到其他应用后该抑制失效 |
| 窗口计数与切换统一逻辑 | 已实现 | 统一使用 AX 窗口列表 |
| 窗口预览（窗口层） | 已实现 | 选中窗口时按需抓图；失败后按 pid+title 重查候选窗口再尝试 |
| 首页窗口 + Tab（首页/监控/预览日志） | 已实现 | 启动自动打开首页，支持独立预览日志页 |
| 监控页日志与手动快照 | 已实现 | 可在应用内查看日志、请求权限、手动采集 |
| 屏幕录制权限提醒与请求 | 已实现 | 监控页显示授权状态，支持一键跳转设置与请求权限 |
| 预览日志独立视图 | 已实现 | 单独过滤 `Preview` 分类日志，便于定位预览失败原因 |
| 固定路径 Release 安装脚本 | 已实现 | `scripts/release-install.sh` 包含退出/构建/安装/启动 |
| 主热键自定义 | 未实现 | 当前热键仍硬编码注册 |
| `Option + Q` 结束高亮应用 | 未实现 | 当前仅有菜单 `Command + Q` 退出自身 |
| 应用层确认仅激活应用（不隐式选窗） | 待校准 | Core 当前在应用层可能返回窗口目标 |

## 运行与开发

### 环境要求

- macOS 14+
- Xcode 15+
- Swift 5.9+

### Xcode 运行

1. 打开 `FlowTabApp.xcodeproj`
2. 选择 `FlowTabApp` Scheme
3. `Cmd + R` 运行

### 命令行构建（Debug）

```bash
xcodebuild \
  -project FlowTabApp.xcodeproj \
  -scheme FlowTabApp \
  -configuration Debug \
  -derivedDataPath ./.build-local \
  build
```

### 一键构建并安装到 `/Applications`（Release）

```bash
chmod +x scripts/release-install.sh
./scripts/release-install.sh
```

脚本会在安装前自动重置该应用的辅助功能与屏幕录制授权记录。  
说明：权限重置依赖 `tccutil`，请在系统 Terminal/iTerm 中执行；受限沙箱环境下会失败。

脚本行为：
1. 退出正在运行的 `FlowTabApp`
2. 重置辅助功能与屏幕录制授权记录
3. 构建 Release
4. 删除旧的 `/Applications/FlowTabApp.app`
5. 复制新包到 `/Applications`
6. 启动应用

### Core 单测

```bash
cd FlowTabCore
swift test
```

## 权限说明

### 辅助功能权限（必须）

用于：
- 枚举 AX 窗口（窗口计数/窗口层候选）
- 执行窗口级激活与聚焦

路径：
- `系统设置 -> 隐私与安全性 -> 辅助功能`

说明：
- 授权后建议完全退出并重启 FlowTabApp，再观察权限状态刷新。

### 屏幕录制权限（窗口预览需要）

用于：
- 抓取窗口预览图（窗口层预览卡片）

路径：
- `系统设置 -> 隐私与安全性 -> 屏幕录制`

说明：
- 未授权不影响切换功能，但会看不到真实窗口预览（显示兜底视图）。

## 常见问题

### 1) 日志里 `trusted=false` 且所有 `windows=0`

通常表示当前运行实例未获得辅助功能授权，或授权对象路径与当前运行实例路径不一致（例如 DerivedData 临时路径实例）。

建议使用 `scripts/release-install.sh` 安装到固定路径 `/Applications/FlowTabApp.app` 后再授权。

### 2) 预览区域没有真实窗口内容

先确认：
- 已进入窗口层
- 当前应用窗口数 `>= 2`
- 已授予屏幕录制权限

否则会展示兜底样式而非真实截图。  
建议切换到 `预览日志` Tab，查看 `Preview` 分类中的 `attempt / capture success / capture failed` 日志。

## 文档维护规则

- 需求变化、交互调整、实现状态变化后，优先更新本 README。
- 若 `requirements.md` 或 `implementation-split.md` 与 README 冲突，以 README 为准。
