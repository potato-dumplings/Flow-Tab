# FlowTab 开发文档

FlowTab 是一个 macOS 应用切换器，目标是在接近系统 `Command + Tab` 手感的前提下，提供更可控的多窗口切换体验。

它当前已支持：
- 全局主切换快捷键自定义（默认 `Option + Tab` / `Option + Shift + Tab`）
- 窗口面板预览与窗口级激活
- 面板内结束应用快捷键自定义（默认 `Option + Q`，语义对齐系统 App Switcher 里的 `Command + Q`）
- 搜索智能匹配（部分匹配、中文分词、拼音全拼/首字母、camelCase 分词、英文缩写、bundle id 关键词）
- 运行时诊断与权限状态可视化

## 功能概览

### 1) 面板模型

FlowTab 当前有三种面板：
- 应用面板：默认由 `Option + Tab` / `Option + Shift + Tab` 打开，用于在应用之间切换。
- 应用面板中的窗口面板：在应用面板会话内进入，用于在当前高亮应用的多个窗口之间切换并预览。
- 独立窗口面板：在窗口内按窗口切换快捷键（默认 `Control + Tab` / `Control + Shift + Tab`）直接进入窗口级切换。

### 1.1) 应用面板排序（MRU）

- 应用面板排序已切换为系统激活顺序驱动的 MRU（Most Recently Used），行为对齐系统 `Command + Tab`。
- 运行中通过系统应用激活/退出事件维护 MRU 列表；最近激活的应用排在最前。
- 自身应用（FlowTab）不参与“激活置顶”，改为按应用打开时间（`launchDate`）参与排序，避免因持续激活导致长期排在最前。
- 冷启动或尚未形成完整激活历史时，会使用当前窗口栈顺序作为兜底，避免列表无序。

### 2) 应用面板中的窗口面板进入规则

- 会话默认从应用面板开始。
- 当高亮应用窗口数 `>= 2` 时，会按“设置 -> 偏好 -> 窗口层自动进入延迟”自动进入窗口面板（默认 `0.75s`）。
- 可在应用面板按 `↓` 手动进入窗口面板。
- 在窗口面板按 `↑` 返回应用面板。
- 如果刚从窗口面板按 `↑` 返回应用面板，本次会话里该应用会临时禁用“自动进入窗口面板”；需要手动按 `↓` 再进入。
- 一旦切到其他应用，这个临时禁用会立即失效。

### 2.1) 独立窗口面板触发规则

- 在前台窗口按窗口切换快捷键（默认 `Control + Tab` / `Control + Shift + Tab`）可直接打开独立窗口面板。
- 若该快捷键与主切换热键冲突，独立窗口面板快捷键会被自动禁用。

### 2.2) 放开主修饰键时的进入规则

- 在应用面板放开主修饰键：确认当前高亮应用，并激活该应用。
- 在应用面板中的窗口面板放开主修饰键：确认当前高亮窗口，并将该窗口切到前台。
- 在独立窗口面板放开主修饰键：确认当前高亮窗口，并将该窗口切到前台。

### 3) 自定义快捷键与结束应用

- 可在应用内 `监控页面 -> 偏好` 自定义：
  - 主修饰键（`Option` / `Control` / `Command`）
  - 主切换按键（Tab / Space / `\`` / A-Z）
  - 结束应用按键（Tab / Space / `\`` / A-Z）
- 默认情况下，`Command + Tab` 会回退为 `Option + Tab`，避免与系统 App Switcher 冲突。
- 可在设置中开启“接管系统 Command + Tab（私有实现）”，让 FlowTab 直接接管 `Command + Tab` / `Command + Shift + Tab`。
- 修改后会自动重注册全局主切换热键，无需重启应用。
- 主切换反向快捷键固定为“主修饰键 + Shift + 主切换按键”。
- 在切换面板可见且按住主修饰键时，按“结束应用按键”会对当前高亮应用发送正常退出请求（`terminate()`）。
- 这是“正常结束”，不是强制结束。
- 若目标应用拒绝退出或已退出，会忽略并保留当前会话。

### 3.1) 系统快捷键接管（无需 Input Monitoring）

如果你不准备上架，可以在 FlowTab 设置里开启“接管系统 Command + Tab（私有实现）”：

- FlowTab 会在运行期间禁用系统 `Command + Tab` / `Command + Shift + Tab`，并注册同名全局热键给自身使用。
- 正常退出时会自动恢复系统快捷键。
- 若异常退出，下次启动会先尝试自动恢复，再根据当前设置决定是否重新接管。

### 4) 窗口标题样式猜测（窗口面板卡片）

为避免“深色标题条 + 浅色窗口”或“浅色标题条 + 深色窗口”的违和，FlowTab 在窗口面板会做标题样式猜测，并仅在以下条件同时满足时执行：

- 通过“独立窗口面板快捷键”进入窗口会话（当前为 `Control + Tab` / `Control + Shift + Tab`；若与主切换热键冲突则该热键会被禁用）
- 已授予屏幕录制权限
- 目标窗口截图成功

不满足任一条件时，不执行猜测，标题样式回退为跟随 FlowTab 当前主题。

### 5) 搜索交互（应用 / 窗口）

为兼顾 `Command + Tab` 的快速切换手感与可输入搜索，搜索能力采用“应用/窗口”双范围设计。

- 搜索范围：`应用` / `窗口`（`窗口` = 按窗口标题搜索）
- 默认范围：`应用`
- 会话打开后默认在应用面板列表，未进入搜索态
- 按 `Enter` 进入搜索态（焦点进入搜索输入）
- 搜索态下按 `Tab` 在 `应用` / `窗口` 间切换
- 搜索态分为“输入焦点 / 结果焦点”：输入焦点下 `←` / `→` 移动光标，结果焦点下 `←` / `→` 切换结果
- 搜索态下按 `↓` 从输入框进入结果列表，按 `↑` 可回到输入框
- 搜索态下如果当前在结果焦点，按 `Esc` 会先回到输入焦点
- `应用` / `窗口` 两个搜索结果列表都支持滚动；键盘上下移动高亮时会自动跟随滚动到可视区域
- 搜索结果列表支持鼠标滚轮与触控板滑动
- 搜索态下 `←` / `→` / `↑` / `↓` 导航为即时切换，不使用过渡动画
- 进入搜索态后，松开主修饰键（例如 `Command`）不会立即关闭面板（固定搜索态）
- `Enter` 激活当前高亮项并关闭，`Esc` 优先清空输入，再退出搜索态
- 搜索态下点击其他应用窗口会立即关闭搜索层（取消当前会话）
- 任务状态（2026-04-04）：三指左/右滑切换 Space 时，“手势动画过程中绝对不闪断”仍受系统手势与窗口层级限制，无法通过公开 API 完整保证。
- 当前策略已更新为：收到 `NSWorkspace.activeSpaceDidChangeNotification` 后，如果主修饰键仍按住，则保留当前会话、临时禁止重新激活 App，并把面板迁移到新的 Space；如果主修饰键已释放，则取消本次会话，避免把用户拉回旧 Space。

匹配能力：
- 部分匹配（无需全名）
- 拼音全拼/首字母匹配（中文友好）
- 英文缩写匹配
- `应用` 范围可匹配 bundle id 关键词（例如 `wechat` 可命中“微信”）
- 为避免泛匹配，`bundle id` 的通用前缀（如 `com` / `org` / `net` / `io`）不会作为命中词

展示约定：
- 搜索栏为横向结构：左侧是当前 query（含光标态），中间是当前高亮结果摘要，右侧是图标
- `应用` 范围：横向行列表（图标 + 应用名）
- `窗口` 范围：横向行列表（图标 + 窗口标题 + 所属应用）；支持按窗口标题与所属应用名联合匹配

### 5.1) 搜索性能策略

当前方案把“正序输入、倒序删除、不规则删除、不规则插入”统一到同一条搜索管线，核心是“本地倒排粗筛 + 轻量精排 + 极简缓存”。

- 作用域隔离：`应用` / `窗口` 各自维护一套索引与缓存，避免互相污染。
- 本地倒排粗筛：会话索引阶段为每个 scope 构建 term + bigram 倒排；缓存 miss 时先粗筛候选，粗筛为空才回退全量集合，保证召回。
- 候选硬上限：粗筛后的候选在精排前按 query 长度和 scope 截断，短 query 限制更严格，用于抑制按键时 CPU 峰值。
- 轻量精排：在候选集上执行简化 `matchScore`（prefix/contains、分词前缀、首字母、bundle id 词项），输出稳定排序。
- 极简缓存：每个 scope 维护 `latestQuery + latestMatchedIndexes` 和小容量 LRU 查询缓存；短 query 使用更小缓存上限，避免内存长期膨胀。
- 可取消调度：每次编辑通过可取消 + 轻量 debounce 的重建调度合并计算，降低高频输入下的瞬时计算压力。

候选来源顺序：
- query 为空：直接返回全列表并清空该 scope 缓存。
- 命中 query 精确缓存：直接复用缓存结果。
- 命中“latestQuery 前缀路径”：复用上次命中索引集合。
- 命中“最近前缀缓存”：逐字符回退找到最近可复用的缓存项。
- 都未命中：走本地倒排粗筛，再进入 `matchScore` 精排；粗筛结果为空时回退全量集合。

### 5.2) 搜索输入实现说明

- 搜索输入已改为接入 macOS 标准文本输入链路，而不是直接消费裸 `keyDown` 字符。
- 搜索头部下面挂了一个隐藏的 `NSTextView`，负责承接字母、数字、中文输入法预编辑、候选词和上屏，再把 query 与光标位置同步回搜索状态。
- 搜索态下如果输入法正处于 marked text 组合阶段，`Enter`、`Esc`、方向键和 `Tab` 等搜索快捷键会先让给系统输入法，避免抢键导致候选词无法确认。
- 2026-03-31 这次修复里，真正拦住输入的根因不是中文匹配，而是搜索面板曾使用 `.nonactivatingPanel`，导致面板不能成为 key window；外层事件监控能看到按键，但 AppKit 文本输入控件收不到事件，所以字母、数字、中文都无法进入搜索框。

## 快捷键

| 场景 | 快捷键 | 行为 |
| --- | --- | --- |
| 全局 | 主修饰键 + 主切换按键（默认 `Option + Tab`） | 打开切换面板并向前切换 |
| 全局 | 主修饰键 + Shift + 主切换按键（默认 `Option + Shift + Tab`） | 打开切换面板并向后切换 |
| 面板内 | `Tab` / `Shift + Tab` | 切换高亮目标 |
| 面板内（非搜索态 / 搜索态结果焦点） | `←` / `→` | 水平切换 |
| 面板内 | `↓` | 进入窗口面板（当窗口数 `>= 2`） |
| 面板内 | `↑` | 从窗口面板返回应用面板 |
| 面板内（应用面板，未进入搜索） | `Enter` | 进入搜索态（焦点进入搜索输入） |
| 面板内（搜索态） | `Tab` | 在搜索范围 `应用` / `窗口` 间切换 |
| 面板内（搜索态，输入焦点） | `←` / `→` | 移动输入光标 |
| 面板内（搜索态） | `↓` | 从搜索输入回到结果列表 |
| 面板内（搜索态） | `↑` | 从结果列表回到搜索输入 |
| 面板内（搜索态） | 鼠标滚轮 / 触控板滑动 | 滚动当前搜索结果列表（应用/窗口） |
| 面板内（搜索态） | 点击其他应用窗口 | 关闭搜索层（取消本次切换） |
| 面板内（搜索态） | 输入法切换快捷键（如 `Control + Space`） | 透传给系统输入法 |
| 面板内（搜索态） | `Enter` | 激活当前高亮搜索结果 |
| 面板内 | 主修饰键 + 结束应用按键（默认 `Option + Q`） | 结束当前高亮应用 |
| 面板内（非搜索态） | `Enter` | 确认当前选择 |
| 面板内 | `Esc` | 取消本次切换 |
| 面板内 | 释放主修饰键 | 根据当前面板确认并进入应用或窗口 |

说明：
- 结束应用快捷键是“面板会话内动作”，即先通过主切换快捷键进入会话，再按结束应用快捷键。
- 释放主修饰键后的进入行为与“2.2) 放开主修饰键时的进入规则”一致。

## 仓库结构

- `FlowTab/`：macOS App 层
- `FlowTabCore/`：核心状态机与模型（可单测）
- `FlowTabTests/`、`FlowTabUITests/`：测试目标
- `scripts/`：构建、发布、压测脚本

### FlowTab App 目录（2026-04-05）

```text
FlowTab/
  App/
    FlowTab.swift
    ContentView.swift
    AppLocalization.swift
  Features/
    Switcher/
      OptionTabHotkeyMonitor.swift
      SwitcherPanel.swift
      SwitcherSearchCoordinator.swift
  Infrastructure/
    Runtime/
      RuntimeBridge.swift
      RuntimeLogging.swift
      RuntimeLogsSection.swift
  TestingSupport/
    AppDelegate+Testing.swift
    FlowTabLaunchTesting.swift
    FlowTabUITestBootstrapper.swift
    NSView+FlowTabTesting.swift
    RuntimeBridge+Testing.swift
  Resources/
    Assets.xcassets
    FlowTab.entitlements
    Preview Content/
      Preview Assets.xcassets
```

### 目录分层逻辑（重排约定）

- `App/`：应用入口、生命周期与根 UI 装配。只放“启动与装配”相关代码，不承载业务细节。
- `Features/`：按业务能力分组（例如 `Switcher`）。同一功能的 monitor / panel / coordinator 放在一起，便于联动修改。
- `Infrastructure/`：对系统 API、运行时快照、日志与桥接的封装。业务层只依赖这里的能力，不直接散落调用系统细节。
- `TestingSupport/`：仅用于测试注入、测试可见性扩展、测试启动辅助。避免与业务代码平铺混放。
- `Resources/`：资源与签名相关文件统一收口（`Assets`、`entitlements`、`Preview Content`），同时同步 Xcode 构建路径。

### 新增文件放置规则

- 新功能先在 `Features/<FeatureName>/` 建目录，再放实现文件；避免直接在 `FlowTab/` 根下加文件。
- 跨功能共用且偏系统能力的代码放 `Infrastructure/`，不要放进任一具体 feature。
- 仅为测试服务的扩展或引导代码放 `TestingSupport/`，命名保持 `+Testing` 或 `...Testing` 语义。
- 资源文件一律放 `Resources/`，移动资源时必须同步更新 `project.pbxproj` 中对应路径配置。

## 技术架构

### Core（FlowTabCore）

- `Preferences`：偏好与切换策略模型
- `Grouping`：应用分组逻辑
- `SwitcherSession`：切换状态机与目标决策

### App（FlowTab）

- `OptionTabHotkeyMonitor`：按用户偏好注册全局主切换热键
- `SwitcherPanelController` + `LiveSwitcherModel`：面板交互、按键处理、会话推进、面板内结束应用快捷键
- `RuntimeSnapshotProvider`：运行中应用与窗口快照
- `RuntimeActivator`：应用/窗口激活
- `RuntimeWindowPreviewProvider`：窗口预览抓图（`ScreenCaptureKit`）与窗口标题样式猜测
- `FlowTab`：应用生命周期、首页、监控页、预览日志页、状态栏菜单

## 环境要求

- macOS 13+
- Xcode 15+
- Swift 5.9+

## 本地运行

### Xcode

1. 打开 `FlowTab.xcodeproj`
2. 选择 `FlowTab` Scheme
3. `Command + R` 运行

### 命令行构建（Debug）

```bash
xcodebuild \
  -project FlowTab.xcodeproj \
  -scheme FlowTab \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath ./.build-local \
  build
```

### Core 单测

```bash
cd FlowTabCore
swift test
```

## 应用内 tab 切换压测

本节按“必跑要求 -> 定位结论 -> 优化落地”组织，三部分是同一条性能治理链路。

### 性能压测（必跑）

涉及以下范围的修改时，提交前必须执行一次 tab 切换压测并记录结果（至少包含 `CPU avg/peak`、`RSS avg/peak`）：
- 左侧 tab 切换相关逻辑或 UI 结构（home / logs / settings）
- 页面生命周期相关状态管理（如 `onAppear` / `onDisappear` / `@StateObject` 保活策略）
- 日志页展示逻辑（含“清空展示但保留文件”的边界行为）

压测命令（参数分别为：持续秒数、切换间隔毫秒、采样间隔秒）：

```bash
./scripts/perf/tab-switch-stress.sh 20 20 0.5
```

建议同时补一组较低频切换对照数据：

```bash
./scripts/perf/tab-switch-stress.sh 20 50 0.5
```

### 压测定位结论（2026-03-30）

说明：以下数据为 `Debug` 构建下的诊断性单轮压测，统一使用 `20s / 20ms / 0.5s sample` 口径，主要用于定位热点来源，不替代上方“性能压测（必跑）”中的正式验收要求。

定义说明：本节中的“全真实页面基线”特指 `Home / Logs / Settings` 三个 tab 都使用真实 SwiftUI 页面实现（非占位视图、非 AppKit 化版本）。

代表性结果如下：

| 实验 | CPU(avg/peak) | RSS(avg/peak) | 结论 |
| --- | --- | --- | --- |
| 全 SwiftUI 实现的真实页面基线 | 69.61% / 79.40% | 83.05MB / 102.31MB | 当前 tab 压测高 CPU 的直接观测值 |
| 关闭 window restoration | 69.50% / 75.10% | 85.87MB / 90.20MB | 几乎无改善，不是主因 |
| 绕过 Home / Logs / Settings 激活副作用 | 69.85% / 95.90% | 93.53MB / 103.44MB | 几乎无改善，不是主因 |
| 三个 tab 全换极简占位视图 | 26.57% / 62.10% | 56.81MB / 61.05MB | 高 CPU 不是“纯切页框架成本” |
| 仅 Home 为真实页面 | 15.53% / 42.10% | 59.14MB / 65.00MB | Home 不是主要热点 |
| 仅 Logs 为真实页面 | 31.99% / 36.40% | 56.24MB / 58.28MB | Logs 中等，不是主因 |
| 仅 Settings 为真实页面 | 79.69% / 105.60% | 97.24MB / 101.69MB | Settings 是主要热点来源 |
| Settings 隐藏即卸载 | 78.47% / 90.00% | 94.30MB / 105.70MB | 反而更差，整页懒挂载不是正确方向 |
| Settings 隐藏态改轻量壳 | 69.40% / 80.10% | 82.30MB / 88.28MB | 内存下降，但 CPU 几乎不变 |
| 全真实页面 + detached Settings root | 79.73% / 98.90% | 101.12MB / 115.89MB | 也更差，单纯切断 `selectedTab -> Settings` 输入链无效 |
| 仅 Settings 为真实页面 + detached Settings root | 81.02% / 97.50% | 88.73MB / 98.56MB | 同样更差，说明热点不只是父级状态传递 |

已确认的结论：
- 这条 benchmark 测到的不是单纯的 tab 切换框架地板。把真实页面全部替换成占位视图后，`CPU avg` 从 `69.61%` 降到 `26.57%`，说明主要成本来自真实页面树本身。
- `window restoration`、Home / Logs / Settings 的激活副作用都不是主因。关闭这些路径后，`CPU avg` 基本仍停留在 `69%` 左右。
- 主要热点集中在 `Settings` 页面，而不是 `Home` 或 `Logs`。单独保留 `Settings` 为真实页面时，`CPU avg` 达到 `79.69%`。
- `Settings` 不能简单改成“隐藏时直接卸载”。在 `20ms` 高频切页下，整页反复重建比继续 keep-alive 更贵。
- `Settings` 隐藏态换成轻量壳也几乎不改变 CPU，说明问题主要不在隐藏态持续参与 diff，而在激活态真实内容的构建与布局。
- 把 `Settings` 放进独立 hosting root，并改为通知式激活，也没有改善 CPU；说明共同问题不只是 `selectedTab` 从父级传入 `Settings` 的更新边界，而更像是真实控件树本身的布局与原生控件同步成本。

进一步拆分 `Settings` 后的结果：

| Settings 实验 | CPU(avg/peak) | 说明 |
| --- | --- | --- |
| 仅保留“外观”卡真实 | 23.80% / 32.50% | 较轻 |
| 仅保留“窗口行为”卡真实 | 31.24% / 54.90% | 中等 |
| 仅保留“权限”卡真实 | 30.04% / 35.70% | 中等 |
| 仅保留“搜索”卡真实 | 29.74% / 35.70% | 中等 |
| 仅保留“快捷键”卡真实 | 68.28% / 94.80% | 最重的单卡 |
| 除“快捷键”外其余卡全部真实 | 68.28% / 72.90% | 其余卡叠加后也同样很重 |

当前可指导优化的结论：
- `Settings` 页的高 CPU 不是某一个单点独占，而是“快捷键卡很重 + 其余卡片叠加也不轻 + 整页双列 `ScrollView` / 布局组合成本高”的共同结果。
- 后续优化应优先聚焦 `Settings` 页内容拆分，而不是继续尝试整页 keep-alive / unmount，或单纯隔离 `selectedTab` 传递路径。
- 最优先的收敛方向是：把 `Settings` 从“整页 live form”改成“摘要页 + 按需编辑器”或更小的按需挂载单元，再单独处理“快捷键”卡这类最重区域。

### Settings 页 AppKit 化（2026-03-31）

本轮把 `Settings` 页整体切换为 AppKit 容器与 AppKit 卡片实现，不再保留“SwiftUI 外层页面 + 多个 AppKit representable 内容岛”的混合结构。

切换原因：
- 旧实现里，`Settings` 页的主要问题已经不只是单张卡片，而是 SwiftUI 与 AppKit 混用后的整体协商成本：尺寸测量、滚动宿主、焦点、留白和原生控件状态同步都更容易漂移。
- 在此前诊断压测中，`Settings` 已经确认是 tab 高频切换 CPU 的主要热点来源；继续在混合结构上做局部修补，收益开始变小，但复杂度持续升高。
- 页面里存在较多表单控件和原生行为诉求，例如首次进入不自动聚焦、点击空白处失焦、输入框与卡片高度精确收口，这些都更适合直接由 AppKit 控制。

这样做的直接收益：
- 布局更稳定：滚动、卡片高度和内容 fitting 都由 AppKit 直接控制，减少 SwiftUI `ScrollView` 与 `NSViewRepresentable` 的测量往返。
- 焦点更稳定：可以明确处理“首次进入设置页不自动聚焦”和“点击其他区域时主动失焦”。
- 样式更可控：按钮、输入框、分段控件、卡片留白都可以持续向旧版视觉靠拢，而不用受系统默认 SwiftUI 包装行为影响。
- 高频切换更可控：去掉混合宿主后，性能问题更容易定位到具体卡片或具体原生控件，而不是卡在跨框架边界。

当前最新压测结果（`Debug`，`30s / 20ms / 0.5s sample`，命令：`./scripts/perf/tab-switch-stress.sh 30 20 0.5`）：

| 版本 | CPU(avg/peak) | RSS(avg/peak) | MEM%(avg/peak) |
| --- | --- | --- | --- |
| 当前 `Settings` 全页 AppKit 化 | 50.54% / 65.40% | 104.23MB / 109.81MB | 0.580% / 0.600% |

结论：
- 与此前 `Settings` 为主要热点的 SwiftUI / 混合结构相比，这一版已经把高频 tab 切换时的 CPU 峰值明显收住。
- 内存占用保持在可接受区间，当前更值得继续优化的是表单密度与局部控件视觉，而不是再回到跨框架混搭。

## 脚本分类

- `scripts/release/release-install.sh`：Release 构建并安装到 `/Applications/Flow Tab.app`。
- `scripts/release/release-dmg.sh`：构建并打包 DMG 到 `release/flowtab-v<version>/`。
- `scripts/release/uninstall-flowtab.js`：生成 DMG 内可双击的一键卸载器。
- `scripts/perf/tab-switch-stress.sh`：tab 高频切换性能压测。

## Release 安装到 /Applications

```bash
chmod +x scripts/release/release-install.sh
./scripts/release/release-install.sh
```

该脚本会执行：
1. 退出正在运行的 `FlowTab`
2. 重置该应用的辅助功能与屏幕录制授权记录
3. 构建 Release
4. 替换 `/Applications/Flow Tab.app`
5. 启动新版本

注意：
- 脚本依赖 `tccutil`，请在 macOS Terminal/iTerm 中执行。
- 在受限沙箱环境中执行会因权限不足失败。

## 生成 DMG（未签名）

```bash
chmod +x scripts/release/release-dmg.sh
./scripts/release/release-dmg.sh
```

输出文件：
- `release/flowtab-v<version>/flowtab-<target>.dmg`（例如 `release/flowtab-v1.0.0/flowtab-universal2-apple-darwin.dmg`）
- 未指定 `--target` 时：若 Release 产物是通用二进制（`arm64 + x86_64`），会生成一个通用 DMG：`flowtab-universal2-apple-darwin.dmg`。
- DMG 内会额外包含 `Uninstall Flow Tab.app`，可用于一键卸载 `/Applications/Flow Tab.app`，并清理权限记录与本地偏好设置。

可选参数：
- `--version <version>`：显式设置发布版本（支持 `1.2.3`、`v1.2.3`、`flowtab-v1.2.3`）
- `--target <target>`：覆盖目标名（例如 `aarch64-apple-darwin`）
- `--skip-build`：跳过构建，直接使用现有 `Release` 产物

说明：
- 这是未签名、未公证的 DMG，首次打开可能触发 Gatekeeper 提示。
- 适合开源阶段给开发者测试使用，不等同于正式分发安装包。
- 推荐 Release tag 命名：`flowtab-v<version>`（例如 `flowtab-v1.0.0`，兼容 `v1.0.0`）。
- 推荐发布方式与 `openai/codex` 风格一致：tag 承载版本，下载资产名保持稳定平台后缀（不带版本号）。
- `release-dmg.sh` 的版本解析顺序是：`--version` -> `GITHUB_REF_NAME` / 当前 commit 上的 release tag -> 否则失败。
- `MARKETING_VERSION` 现在只负责 app 内显示版本；脚本会校验它和发布版本一致，但不会再把它当成 DMG 版本来源。

推荐流程：
1. 先把 `FlowTab` target 的 `MARKETING_VERSION` 更新到将发布的版本号，例如 `1.0.0`。
2. 提交版本变更。
3. 在待发布 commit 上打 tag：`flowtab-v1.0.0`。
4. 在该 tag 上运行 `scripts/release/release-dmg.sh`，或在 GitHub Release / tag workflow 中直接调用它。
5. 若只是本地预打包验证、还没打 tag，可临时传 `--version 1.0.0`。

发布示例（GitHub CLI）：

```bash
TAG="flowtab-v1.0.0"
bash scripts/release/release-dmg.sh
gh release create "${TAG}" release/"${TAG}"/flowtab-universal2-apple-darwin.dmg --title "${TAG}"
```

## 权限说明

### 辅助功能（必须）

用途：
- 枚举 AX 窗口（窗口计数与窗口面板候选）
- 执行窗口聚焦与提升

系统路径：
- `系统设置 -> 隐私与安全性 -> 辅助功能`

### 屏幕录制（窗口预览需要）

用途：
- 窗口面板卡片真实截图
- 窗口标题样式猜测（深色/浅色）

系统路径：
- `系统设置 -> 隐私与安全性 -> 屏幕录制`

未授予屏幕录制权限时，不影响切换功能，但预览会回退为兜底样式，且不会执行标题样式猜测。

## 常见问题

### 1) 看不到可切换窗口，日志里 `windows=0`

通常是辅助功能权限未生效，或者当前运行实例路径与授权路径不一致。
建议安装到固定路径 `/Applications/Flow Tab.app` 后重新授权。

### 2) 窗口预览没有真实画面

请检查：
- 是否已进入窗口面板
- 目标应用是否存在 `>= 2` 个可切换窗口
- 是否已授予屏幕录制权限

可在应用的“预览日志”页查看 `Preview` 分类日志定位问题。

### 3) 结束应用快捷键没有触发

请确认：
- 当前处于切换面板会话中（面板可见）
- 正在按住你配置的主修饰键
- 按下的是你在“监控页面 -> 偏好”里配置的结束应用按键

结束应用快捷键不是全局独立动作，而是面板内动作。

### 4) 搜索态里松开 `Command` 面板为什么不关闭

这是搜索交互的固定模式设计：进入搜索态后需要连续输入，因此松开 `Command` 会保持面板打开，直到用户确认（`Enter`）或取消（`Esc`）。

## 设置项（搜索）

`监控页面 -> 偏好` 已支持以下搜索相关设置：
- 启用搜索功能（关闭后面板不显示搜索栏，且不会进入搜索态）
- 默认搜索范围（`应用` / `窗口`，默认 `应用`）

## 设置项（外观与语言）

`设置 -> 外观` 当前包含以下与语言相关的能力：
- 语言下拉（系统默认样式）
- 当前支持 `中文` 与 `English` 切换
- 主题模式（跟随系统 / 浅色 / 深色）

语言切换行为：
- 切换后会刷新首页、日志页、设置页、命令菜单、状态栏菜单与搜索面板文案
- 语言偏好会持久化到本地（`appLanguage`）

扩展约定（新增第三种语言时）：
- 在 `AppLanguage` 中新增语言枚举
- 在 `AppStrings` 里补充对应文案映射
- 外观页语言下拉会按 `AppLanguage.allCases` 自动展示

## 开发状态

已实现：
- 主切换、应用面板/窗口面板/独立窗口面板导航
- 窗口预览与失败兜底
- 主切换与结束应用快捷键自定义
- 切换面板搜索（`应用` / `窗口`）：支持部分匹配、中文分词、camelCase 分词、拼音全拼/首字母、英文缩写、bundle id 关键词匹配，且透传输入法切换快捷键
- 首页、监控页、预览日志页

## 文档维护约定

- 本仓库以 `docs/DEVELOPMENT.md` 作为需求与实现状态基线文档。
- 详细项目文档统一放在 `docs/` 目录下维护。
- 根目录 `README.md` 面向使用者，保持安装与使用说明。
- 根目录 `AGENTS.md` 只保留项目入口级工程约束。
- `FlowTabCore/docs/requirements.md` 与 `FlowTabCore/docs/implementation-split.md` 仅保留跳转说明。

## 搜索压测要求（必须）

凡是修改以下内容，提交前必须执行“高窗口数搜索”压测，并附结果：
- `SwitcherSearchCoordinator` 的匹配、缓存、候选集选择逻辑
- 搜索输入节流/异步调度逻辑
- 可能影响搜索路径 CPU 或内存占用的相关代码

压测最小要求：
- 数据规模：不少于 `10,000` 窗口（例如 `400 apps x 25 windows`）
- 采样：每 `0.5s` 采集 `%CPU` 与 `RSS`
- 时长：单场景不少于 `30s`
- 场景：至少覆盖 `realistic`（真实输入节奏）与 `stress`（持续高频输入）

结果产出要求：
- 输出 `%CPU` 与内存（RSS）曲线数据（CSV 或等价格式）
- 给出 `avg / p95 / max` 与吞吐（每 30s 按键数）
- 与上一版基线对比，说明是否有回归及原因

判定原则：
- 不接受“无解释的持续 CPU 回归”
- 不接受“热身后仍持续单调上涨”的 RSS 走势（疑似内存泄漏）

### 最近一次快速基线（A-only）

执行时间：`2026-03-29`

执行命令：
```bash
xcodebuild \
  -project FlowTab.xcodeproj \
  -scheme FlowTab \
  -destination "platform=macOS,arch=$(uname -m)" \
  -only-testing:FlowTabTests/FlowTabTests/testSearchPerformanceWindowScope \
  -only-testing:FlowTabTests/FlowTabTests/testSearchPressureWindowScopeUnified \
  test
```

数据集（两条用例一致）：
- `400 apps x 25 windows = 10,000 windows`
- `rounds = 3`
- `queries = 120`

结果：
- `testSearchPerformanceWindowScope`：`build=844.84ms`，`query=1630.67ms`，`throughput=73.59 qps`，用例总耗时 `3.334s`
- `testSearchPressureWindowScopeUnified`：`build=828.06ms`，`query=1618.97ms`，`throughput=74.12 qps`，用例总耗时 `3.289s`

说明：
- 该基线用于快速回归检查（算法路径与吞吐）。
- 完整发布前压测仍需按上文要求补齐 `30s` 的 `%CPU/RSS` 采样与 `avg/p95/max` 对比。
