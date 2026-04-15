# Space Fixture App Workflow

## 背景

当前 FlowTab 的自动化测试主要覆盖两类能力：

- 通过 `--flowtab-ui-mock-runtime` 注入运行时快照，验证 UI 展示和交互逻辑。
- 通过 `handleActiveSpaceDidChangeForTesting()` 或发布 `NSWorkspace.activeSpaceDidChangeNotification`，验证收到空间变化信号后的恢复与取消策略。

这些测试可以稳定覆盖 FlowTab 自身的逻辑判断，但不能直接证明 XCTest 已真实驱动 macOS 完成以下行为：

- 单应用多窗口跨 Space 的真实运行时拓扑
- fullscreen Space 的生成与切换
- 应用内多标签窗口对真实窗口标题的影响
- 多个真实应用并存时的 runtime snapshot 与分组结果

为补充这部分验证，仓库当前提供了一个测试专用 app target：`FlowTabSpaceFixture`。

## 当前实现总览

当前仓库里的实现不是“未来要做的方案草图”，而是已经落地的两层能力：

- 一个模板 target：`FlowTabSpaceFixture`
- 两种启动模式：
  - 单 app 扁平参数模式
  - workflow 配置模式

其中：

- 单 app 模式已经接入现有 FlowTab 真实环境 UI 用例。
- workflow 模式已经接入 fixture app 自身的配置解析、窗口规划和 UI 渲染测试。
- workflow 模式当前支持“按 appID 启动某一个 app 变体”，但仓库里还没有统一的一键多 app 启动器把所有 app 一次性拉起后再驱动 FlowTab。

因此，当前实现应理解为：

- `FlowTabSpaceFixture` 已经能表达多窗口、fullscreen、应用内 tab。
- `build-space-fixture-workflow.sh` 已经能生成多 app bundle 变体和 resolved workflow JSON。
- FlowTab 端到端真实 UI workflow 目前仍主要跑单 app 路径。

## 当前目标边界

`FlowTabSpaceFixture` 当前负责的是“制造受控的真实应用窗口拓扑”，不负责：

- 替代现有 unit、behavior、UI 主覆盖链路
- 作为稳定 CI 的唯一空间验证方案
- 复刻真实 Chrome、Finder、Notes 的全部交互逻辑
- 把测试专用逻辑混入 FlowTab 生产路径

## Target 与文件入口

当前相关实现主要分布在以下位置：

- [FlowTabSpaceFixture/FlowTabSpaceFixtureApp.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabSpaceFixture/FlowTabSpaceFixtureApp.swift)
- [FlowTabSpaceFixture/SpaceFixtureAppDelegate.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabSpaceFixture/SpaceFixtureAppDelegate.swift)
- [FlowTabSpaceFixture/SpaceFixtureLaunchConfiguration.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabSpaceFixture/SpaceFixtureLaunchConfiguration.swift)
- [FlowTabSpaceFixture/SpaceFixtureWorkflowConfiguration.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabSpaceFixture/SpaceFixtureWorkflowConfiguration.swift)
- [FlowTabSpaceFixture/SpaceFixtureWindowPlan.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabSpaceFixture/SpaceFixtureWindowPlan.swift)
- [FlowTabSpaceFixture/SpaceFixtureWindowCoordinator.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabSpaceFixture/SpaceFixtureWindowCoordinator.swift)
- [FlowTabSpaceFixture/SpaceFixtureWindowContentView.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabSpaceFixture/SpaceFixtureWindowContentView.swift)
- [scripts/testing/build-space-fixture-app.sh]({user-home}/Projeck-Works/Personal/FlowTabApp/scripts/testing/build-space-fixture-app.sh)
- [scripts/testing/build-space-fixture-workflow.sh]({user-home}/Projeck-Works/Personal/FlowTabApp/scripts/testing/build-space-fixture-workflow.sh)

## 当前支持的两种启动模式

### 1. 单 app 扁平参数模式

这是当前 FlowTab 真实环境 UI 用例实际在用的路径。

支持的主要参数有：

- `--window-count <N>`
- `--fullscreen-window-index <index>`
- `--window-title-prefix <prefix>`
- `--staggered-layout`
- `--enter-fullscreen-delay-ms <value>`
- `--preserve-desktop-after-fullscreen`

示例：

```text
/path/to/Chrome Fixture.app/Contents/MacOS/FlowTabSpaceFixture \
  --window-count 3 \
  --fullscreen-window-index 3 \
  --window-title-prefix "Workflow" \
  --staggered-layout \
  --enter-fullscreen-delay-ms 5000 \
  --preserve-desktop-after-fullscreen
```

该模式的特点：

- 适合单应用多窗口 smoke 和当前现有真实环境回归。
- 由 fixture app 自己生成窗口标题，例如 `Workflow 1`、`Workflow 2`、`Workflow 3`。
- 可指定一个窗口在启动后自动进入 fullscreen。
- 若启用 `--preserve-desktop-after-fullscreen`，fullscreen 后会重新把普通桌面窗口拉回前台，便于 FlowTab 采样。

### 2. workflow 配置模式

这是当前仓库里已经实现但尚未全面接入 FlowTab 端到端真实 UI 用例的路径。

支持的主要参数有：

- `--workflow-config <path>`
- `--workflow-app-id <id>`
- `--staggered-layout`
- `--enter-fullscreen-delay-ms <value>`
- `--preserve-desktop-after-fullscreen`

示例：

```text
/path/to/Chrome Fixture.app/Contents/MacOS/FlowTabSpaceFixture \
  --workflow-config /absolute/path/to/resolved-workflow.json \
  --workflow-app-id chrome \
  --staggered-layout
```

该模式的特点：

- 进程启动时只读取 workflow 中属于当前 `appID` 的那一段配置。
- 一个 `FlowTabSpaceFixture` 进程对应一个 workflow app。
- 如果要同时启动多个 app，需要外部脚本或测试驱动层分别启动多个 app 变体。

## 当前 workflow 数据模型

当前实现已经支持以下层级：

| 层级 | 当前字段 |
| --- | --- |
| Workflow | `workflowName`、`settleTimeoutMs`、`apps` |
| App | `appID`、`appName`、`bundleId`、`appPath`、`launchOrder`、`windows` |
| Window | `title`、`mode`、`tabs` |
| Tab | `title`、`isSelected`、`identifier` |

当前 `mode` 支持：

- `standard`
- `fullscreen`

示例：

```json
{
  "workflowName": "multi-app-space-topology",
  "settleTimeoutMs": 8000,
  "apps": [
    {
      "appID": "finder",
      "appName": "Finder Fixture",
      "bundleId": "com.example.fixture.finder",
      "launchOrder": 1,
      "windows": [
        {
          "title": "Finder Main",
          "mode": "standard",
          "tabs": []
        }
      ]
    },
    {
      "appID": "chrome",
      "appName": "Chrome Fixture",
      "bundleId": "com.example.fixture.chrome",
      "launchOrder": 2,
      "windows": [
        {
          "title": "Chrome Window 1",
          "mode": "standard",
          "tabs": [
            { "title": "Docs", "isSelected": true },
            { "title": "PR", "isSelected": false }
          ]
        },
        {
          "title": "Chrome Window 2",
          "mode": "fullscreen",
          "tabs": [
            { "title": "Mail", "isSelected": true },
            { "title": "Calendar", "isSelected": false }
          ]
        }
      ]
    }
  ]
}
```

## 当前窗口与标签行为

当前实现里，window 和 tab 的关系不是未来设计，而是已经体现在启动配置归一化和窗口渲染里的行为：

- `tabs` 为空时，该窗口就是普通窗口。
- `tabs` 非空时，该窗口表示“应用内部自己管理的 tab 模型”。
- 当前实现会把第一个 `isSelected = true` 的 tab 视为当前选中 tab。
- 如果没有任何 tab 标记为选中，则会把第一个 tab 归一化为选中状态。
- 当前选中 tab 的标题会成为窗口的真实标题。
- 原始 window `title` 不会丢失，而是作为 subtitle 展示出来。

例如：

- window 配置标题为 `Chrome Window 1`
- tab 为 `Docs`、`PR`
- `Docs` 被标记为 `isSelected = true`

则当前窗口会表现为：

- 窗口标题：`Docs`
- 窗口副标题：`Chrome Window 1`

这就是当前仓库用来覆盖 Chrome 类场景的方式。

## 当前对系统 window tabbing 的处理

当前实现明确区分两种 tab：

- macOS 自动 window tabbing
- 应用内部自定义 tab

`FlowTabSpaceFixture` 当前固定关闭系统 automatic window tabbing：

- `NSWindow.allowsAutomaticWindowTabbing = false`
- `window.tabbingMode = .disallowed`

因此，当前 workflow 配置里的 `tabs` 只表示应用内 tab，不表示系统层面的 window tabbing。

## 当前 Fixture App 可观测信号

为了让 XCTest 稳定观测 fixture app 状态，当前窗口内容会暴露以下信息：

- workflow ready 标记：`flowtab.spacefixture.workflow.ready`
- workflow summary 标记：`flowtab.spacefixture.workflow.summary`
- 每个窗口标题标记：`flowtab.spacefixture.window.title.<index>`
- 每个窗口副标题标记：`flowtab.spacefixture.window.subtitle.<index>`
- 每个窗口模式标记：`flowtab.spacefixture.window.mode.<index>`
- 每个窗口 tab 标记：`flowtab.spacefixture.window.tab.<windowIndex>.<tabIndex>`
- 每个窗口当前选中 tab 摘要：`flowtab.spacefixture.window.selected-tab.<index>`

其中 workflow summary 当前展示的是“归一化后的窗口标题列表”，也就是 FlowTab 更关心的真实窗口标题，而不是原始配置标题。

## 当前构建脚本

### `build-space-fixture-app.sh`

当前用途：

- 构建 `FlowTabSpaceFixture` 模板 app
- 复制一个 app bundle 变体
- 重写 `CFBundleDisplayName`
- 重写 `CFBundleIdentifier`
- 重新签名

示例：

```bash
./scripts/testing/build-space-fixture-app.sh \
  --app-name "Chrome Fixture" \
  --bundle-id "com.example.chrome.fixture"
```

该脚本适合：

- 单 app 路径
- 当前 FlowTab 真实环境 UI 用例
- 手工本地验证

### `build-space-fixture-workflow.sh`

当前用途：

- 构建一次 `FlowTabSpaceFixture` 模板 app
- 为 workflow 中每个 app 生成对应的 app bundle 变体
- 把每个变体的绝对 `appPath` 回写到 resolved workflow JSON

示例：

```bash
./scripts/testing/build-space-fixture-workflow.sh \
  --workflow-config /absolute/path/to/workflow.json
```

运行后会得到：

- 多个 fixture app 变体
- 一份 resolved workflow JSON

resolved workflow JSON 里的每个 app 会包含：

- `appName`
- `bundleId`
- `appPath`

这份文件当前适合给外部启动器、手工测试或后续测试驱动层读取。

## 当前测试接入情况

### 已接入的逻辑与行为测试

当前以下能力已经有自动化覆盖：

- workflow 配置解析
- tab 归一化
- fullscreen window 标记
- window planner 生成结果
- coordinator 对窗口显示和 fullscreen 调度的处理

对应测试主要在：

- [FlowTabTests+SpaceFixtureLaunchConfiguration.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabTests/FlowTabTests+SpaceFixtureLaunchConfiguration.swift)
- [FlowTabTests+SpaceFixtureWindowCoordinator.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabTests/FlowTabTests+SpaceFixtureWindowCoordinator.swift)

### 已接入的 fixture app UI 测试

当前 workflow 模式已经有 fixture app 自身的 UI 用例覆盖：

- [FlowTabUITests+SpaceFixtureWorkflowConfiguration.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabUITests/FlowTabUITests+SpaceFixtureWorkflowConfiguration.swift)

该用例当前验证：

- workflow 文件能正确驱动 tabbed windows
- 当前选中 tab 会成为窗口标题
- 原始 window title 会作为 subtitle 保留
- tab strip 与 selected-tab 标识可被 XCTest 观测

### 当前仍在使用单 app 路径的 FlowTab 真实环境用例

当前真实环境 FlowTab UI workflow 仍主要通过单 app 路径启动 fixture app，相关 helper 在：

- [FlowTabUITests+SpaceFixtureApp.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabUITests/FlowTabUITests+SpaceFixtureApp.swift)
- [FlowTabUITests+SpaceFixtureWorkflow.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabUITests/FlowTabUITests+SpaceFixtureWorkflow.swift)

当前这条链路使用的环境变量仍是：

- `FLOWTAB_SPACE_FIXTURE_APP_PATH`
- `FLOWTAB_SPACE_FIXTURE_BUNDLE_ID`

也就是说：

- 多 app workflow 构建和 per-app 启动能力已经实现
- 但 FlowTab 真实 runtime end-to-end UI 用例当前还没有统一切换到 resolved workflow JSON

## 当前限制

- 仓库里目前没有统一的 workflow 启动器去一次性启动多个 fixture app。
- `build-space-fixture-workflow.sh` 当前只负责生成 app 变体和 resolved workflow JSON，不负责把所有 app 拉起。
- FlowTab 真实环境 UI workflow 当前仍主要验证单 app 多窗口路径。
- 仓库当前没有消费 `FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH` 的现成测试入口。
- Mission Control 动画和 `activeSpaceDidChange` 的系统级时序仍不适合做精确帧级断言。
- 这套机制更适合本地回归和低频集成，不适合作为唯一稳定 CI 依据。

## 当前推荐用法

如果要做当前仓库已经完全打通的回归路径，优先使用：

- `build-space-fixture-app.sh`
- 单 app 扁平参数模式
- 现有 FlowTab 真实环境 UI tests

如果要验证当前已经实现的 workflow/tab 能力，优先使用：

- `build-space-fixture-workflow.sh`
- `--workflow-config` + `--workflow-app-id`
- fixture app 自身的 UI/配置测试

如果要继续把多 app workflow 接到 FlowTab 真实 runtime end-to-end 测试，需要新增一层“统一启动所有 workflow app 并把结果传给 FlowTab UI 测试”的驱动逻辑；这部分当前不属于已实现范围。

## 当前结论

当前 `SPACE_FIXTURE_APP_WORKFLOW` 的实际状态可以概括为：

- 已实现一个模板 fixture app：`FlowTabSpaceFixture`
- 已实现单 app 多窗口与 fullscreen 路径
- 已实现 workflow 配置解析与应用内 tab 模型
- 已实现 workflow 级 app 变体构建脚本
- 已实现 fixture app 自身对 tabbed window 的 UI 覆盖
- 尚未把多 app workflow 全量接到 FlowTab 真实 runtime end-to-end UI workflow

因此，这份文档应按“当前实现说明”理解，而不是“未来设计提案”。
