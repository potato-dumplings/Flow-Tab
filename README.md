# FlowTabApp

FlowTabApp 是一个 macOS 应用切换器，目标是在接近系统 `Command + Tab` 手感的前提下，提供更可控的多窗口切换体验。

它当前已支持：
- 全局主切换快捷键自定义（默认 `Option + Tab` / `Option + Shift + Tab`）
- 窗口层预览与窗口级激活
- 面板内结束应用快捷键自定义（默认 `Option + Q`，语义对齐系统 App Switcher 里的 `Command + Q`）
- 运行时诊断与权限状态可视化

## 功能概览

### 1) 切换层级

FlowTab 使用三层会话模型：
- 应用层：在应用之间切换
- 分组层：在应用分组之间切换
- 窗口层：在同一应用的多个窗口之间切换并预览

### 2) 窗口层进入规则

- 会话默认从应用层开始。
- 当高亮应用窗口数 `>= 2` 时，会按“设置 -> 偏好 -> 窗口层自动进入延迟”自动进入窗口层（默认 `0.35s`）。
- 可在应用层按 `↓` 手动进入窗口层。
- 在窗口层按 `↑` 返回应用层。
- 如果刚从窗口层按 `↑` 返回应用层，本次会话里该应用会临时禁用“自动进入窗口层”；需要手动按 `↓` 再进入。
- 一旦切到其他应用，这个临时禁用会立即失效。

### 3) 自定义快捷键与结束应用

- 可在应用内 `监控页面 -> 偏好` 自定义：
  - 主修饰键（`Option` / `Control` / `Command`）
  - 主切换按键（Tab / Space / `\`` / A-Z）
  - 结束应用按键（Tab / Space / `\`` / A-Z）
- 修改后会自动重注册全局主切换热键，无需重启应用。
- 主切换反向快捷键固定为“主修饰键 + Shift + 主切换按键”。
- 在切换面板可见且按住主修饰键时，按“结束应用按键”会对当前高亮应用发送正常退出请求（`terminate()`）。
- 这是“正常结束”，不是强制结束。
- 若目标应用拒绝退出或已退出，会忽略并保留当前会话。

## 快捷键

| 场景 | 快捷键 | 行为 |
| --- | --- | --- |
| 全局 | 主修饰键 + 主切换按键（默认 `Option + Tab`） | 打开切换面板并向前切换 |
| 全局 | 主修饰键 + Shift + 主切换按键（默认 `Option + Shift + Tab`） | 打开切换面板并向后切换 |
| 面板内 | `Tab` / `Shift + Tab` | 切换高亮目标 |
| 面板内 | `←` / `→` | 水平切换 |
| 面板内 | `↓` | 进入窗口层（当窗口数 `>= 2`） |
| 面板内 | `↑` | 从窗口层返回应用层 |
| 面板内 | 主修饰键 + 结束应用按键（默认 `Option + Q`） | 结束当前高亮应用 |
| 面板内 | `Enter` | 确认当前选择 |
| 面板内 | `Esc` | 取消本次切换 |
| 面板内 | 释放主修饰键 | 确认当前选择 |

说明：结束应用快捷键是“面板会话内动作”，即先通过主切换快捷键进入会话，再按结束应用快捷键。

## 仓库结构

- `FlowTabApp/`：macOS App 层（热键、面板、运行时桥接、首页与监控 UI）
- `FlowTabCore/`：核心状态机与模型（可单测）
- `FlowTabAppTests/`、`FlowTabAppUITests/`：测试目标
- `scripts/`：构建与安装脚本

## 技术架构

### Core（FlowTabCore）

- `Preferences`：偏好与切换策略模型
- `Grouping`：应用分组逻辑
- `SwitcherSession`：切换状态机与目标决策

### App（FlowTabApp）

- `OptionTabHotkeyMonitor`：按用户偏好注册全局主切换热键
- `SwitcherPanelController` + `LiveSwitcherModel`：面板交互、按键处理、会话推进、面板内结束应用快捷键
- `RuntimeSnapshotProvider`：运行中应用与窗口快照
- `RuntimeActivator`：应用/窗口激活
- `RuntimeWindowPreviewProvider`：窗口预览抓图（`CGWindowListCreateImage`）
- `FlowTabAppApp`：应用生命周期、首页、监控页、预览日志页、状态栏菜单

## 环境要求

- macOS 14+
- Xcode 15+
- Swift 5.9+

## 本地运行

### Xcode

1. 打开 `FlowTabApp.xcodeproj`
2. 选择 `FlowTabApp` Scheme
3. `Command + R` 运行

### 命令行构建（Debug）

```bash
xcodebuild \
  -project FlowTabApp.xcodeproj \
  -scheme FlowTabApp \
  -configuration Debug \
  -derivedDataPath ./.build-local \
  build
```

### Core 单测

```bash
cd FlowTabCore
swift test
```

## Release 安装到 /Applications

```bash
chmod +x scripts/release-install.sh
./scripts/release-install.sh
```

该脚本会执行：
1. 退出正在运行的 `FlowTabApp`
2. 重置该应用的辅助功能与屏幕录制授权记录
3. 构建 Release
4. 替换 `/Applications/FlowTabApp.app`
5. 启动新版本

注意：
- 脚本依赖 `tccutil`，请在 macOS Terminal/iTerm 中执行。
- 在受限沙箱环境中执行会因权限不足失败。

## 权限说明

### 辅助功能（必须）

用途：
- 枚举 AX 窗口（窗口计数与窗口层候选）
- 执行窗口聚焦与提升

系统路径：
- `系统设置 -> 隐私与安全性 -> 辅助功能`

### 屏幕录制（窗口预览需要）

用途：
- 窗口层卡片真实截图

系统路径：
- `系统设置 -> 隐私与安全性 -> 屏幕录制`

未授予屏幕录制权限时，不影响切换功能，但预览会回退为兜底样式。

## 常见问题

### 1) 看不到可切换窗口，日志里 `windows=0`

通常是辅助功能权限未生效，或者当前运行实例路径与授权路径不一致。
建议安装到固定路径 `/Applications/FlowTabApp.app` 后重新授权。

### 2) 窗口预览没有真实画面

请检查：
- 是否已进入窗口层
- 目标应用是否存在 `>= 2` 个可切换窗口
- 是否已授予屏幕录制权限

可在应用的“预览日志”页查看 `Preview` 分类日志定位问题。

### 3) 结束应用快捷键没有触发

请确认：
- 当前处于切换面板会话中（面板可见）
- 正在按住你配置的主修饰键
- 按下的是你在“监控页面 -> 偏好”里配置的结束应用按键

结束应用快捷键不是全局独立动作，而是面板内动作。

## 开发状态

已实现：
- 主切换、分组层/窗口层导航
- 窗口预览与失败兜底
- 主切换与结束应用快捷键自定义
- 首页、监控页、预览日志页

## 文档维护约定

- 本仓库以根目录 `README.md` 作为唯一需求与实现状态基线文档。
- `FlowTabCore/docs/requirements.md` 与 `FlowTabCore/docs/implementation-split.md` 仅保留跳转说明。
