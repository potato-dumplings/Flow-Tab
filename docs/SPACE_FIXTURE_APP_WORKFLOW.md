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
- FlowTab 端到端真实 UI workflow 已开始消费 multi-app resolved workflow JSON，当前覆盖 `Home` 多 app 路径和 `Switcher` app strip 路径；其余更细的 switcher/search 场景仍在逐步接入。

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

### 运行真实环境 multi-app UI workflow 的本地前置条件

对于会真实拉起 `FlowTabSpaceFixture` app 变体并驱动 FlowTab 首页或 switcher 的 UI 用例，本地环境除了 fixture app 本身外，还需要满足以下条件：

- FlowTab 已授予 `Accessibility`
- FlowTab 已授予 `Screen & System Audio Recording`
- `Flow Tab.app` 与 `Flow Tab UITest.app` 使用同一套 macOS code identity，而不是一份 `adhoc`、一份 `Apple Development`

这里要注意：

- macOS 隐私权限实际绑定的是 app 的 code identity，不是单纯绑定文件名或 bundle id。
- 如果 `/Applications/Flow Tab.app` 仍然是 `adhoc`，而 UI tests 启动的是另一份 `Apple Development` 签名的 `Flow Tab UITest.app`，系统可能不会复用你已经授过的权限。

当前推荐的本地准备方式：

1. 安装固定路径的 UI test app：

```bash
./scripts/testing/install-ui-test-app.sh --development-team <TEAM_ID>
```

默认会安装到：

- `~/Applications/Flow Tab UITest.app`

2. 确保平时运行的 `/Applications/Flow Tab.app` 也使用同一套本地开发签名。

如果需要覆盖安装到固定路径，可使用：

```bash
./scripts/testing/install-ui-test-app.sh \
  --development-team <TEAM_ID> \
  --install-path "/Applications/Flow Tab.app"
```

3. 在下面两处确认 `Flow Tab` 已授权：

- `系统设置 -> 隐私与安全性 -> 辅助功能`
- `系统设置 -> 隐私与安全性 -> 屏幕与系统音频录制`

4. 再运行：

```bash
./scripts/testing/run-ui-tests-local.sh
```

该脚本当前会：

- 优先启动固定路径 `~/Applications/Flow Tab UITest.app`
- 对本地 UI test 构建产物默认关闭代码签名，避免测试执行再次受 Xcode 当前签名配置影响

如果之前已经给 `/Applications/Flow Tab.app` 授权，但真实环境 workflow 用例仍在首页看到权限引导按钮，优先检查的不是“有没有授权”，而是“`Flow Tab.app` 和 `Flow Tab UITest.app` 当前是不是同一个签名身份”。

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

### 已接入的 FlowTab multi-app 真实环境 UI 用例

当前已补上基于 resolved workflow JSON 的 multi-app `Home` 和 `Switcher` E2E 用例：

- [FlowTabUITests+SpaceFixtureMultiAppWorkflow.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabUITests/FlowTabUITests+SpaceFixtureMultiAppWorkflow.swift)
- [space-fixture-home-multi-app-workflow.json]({user-home}/Projeck-Works/Personal/FlowTabApp/docs/fixtures/space-fixture-home-multi-app-workflow.json)
- [space-fixture-home-fullscreen-only-workflow.json]({user-home}/Projeck-Works/Personal/FlowTabApp/docs/fixtures/space-fixture-home-fullscreen-only-workflow.json)
- [FlowTabUITests+SpaceFixtureSwitcherMultiAppWorkflow.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabUITests/FlowTabUITests+SpaceFixtureSwitcherMultiAppWorkflow.swift)
- [space-fixture-switcher-multi-app-workflow.json]({user-home}/Projeck-Works/Personal/FlowTabApp/docs/fixtures/space-fixture-switcher-multi-app-workflow.json)

这些用例当前验证：

- `Home` 页会同时展示多个 workflow app row
- `finder(1)`、`chrome(3, 含 1 个 fullscreen)`、`notes(1)` 的 `windowCount` 会分别显示为 `1w / 3w / 1w`
- `Home` 页切换不同 workflow app 后，窗口区只展示当前 app 的 resolved window titles，不混入其他 workflow app 的窗口标题
- `fullscreen-only` app 与普通 app 共存时，`Home` 页仍会展示该 app，且选中后仍能看到它的 resolved window title
- `Switcher` app strip 会同时暴露 workflow 中至少 3 个真实 app 的 `flowtab.switcher.app.*` accessibility anchors
- workflow 模式下的 per-app 启动顺序、resolved window title 和 fullscreen 标记会被测试驱动层正确读取

该链路当前优先读取：

- `FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH`
- 默认输出路径 `./.build-local/space-fixture-workflow/variants/resolved-workflow.json`

### 当前仍主要使用单 app 路径的 FlowTab 真实环境用例

当前真实环境 FlowTab UI workflow 仍主要通过单 app 路径启动 fixture app，相关 helper 在：

- [FlowTabUITests+SpaceFixtureApp.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabUITests/FlowTabUITests+SpaceFixtureApp.swift)
- [FlowTabUITests+SpaceFixtureWorkflow.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabUITests/FlowTabUITests+SpaceFixtureWorkflow.swift)

当前这条链路使用的环境变量仍是：

- `FLOWTAB_SPACE_FIXTURE_APP_PATH`
- `FLOWTAB_SPACE_FIXTURE_BUNDLE_ID`

也就是说：

- 多 app workflow 构建和 per-app 启动能力已经实现
- FlowTab 真实 runtime end-to-end UI 用例已经开始消费 resolved workflow JSON，当前已覆盖 `Home` 多 app 计数、app 切换后的窗口列表隔离、`fullscreen-only app` 的稳定展示，以及 `Switcher` app strip 展示
- 更大范围的 `Switcher` preview、search、列表隔离等 multi-app 用例仍未全部切到这条链路

## 当前限制

- 仓库里目前没有面向生产代码或通用脚本的一键 workflow 启动器；当前多 app 启动逻辑主要存在于 `FlowTabUITests` 的测试 helper 内。
- `build-space-fixture-workflow.sh` 当前只负责生成 app 变体和 resolved workflow JSON，不负责把所有 app 拉起。
- FlowTab 真实环境 UI workflow 当前仍主要验证单 app 多窗口路径。
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

如果要运行当前已经接入的 multi-app `Home` 回归，优先使用：

- `build-space-fixture-workflow.sh --workflow-config docs/fixtures/space-fixture-home-multi-app-workflow.json`
- 默认输出的 `resolved-workflow.json`，或通过 `FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH` 显式指定路径
- [FlowTabUITests+SpaceFixtureMultiAppWorkflow.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabUITests/FlowTabUITests+SpaceFixtureMultiAppWorkflow.swift)

其中：

- `space-fixture-home-multi-app-workflow.json` 直接对应默认生成的 `resolved-workflow.json`
- `space-fixture-home-fullscreen-only-workflow.json` 会在 UI 测试里复用同一批已构建的 fixture app 变体，并临时生成场景专用的 resolved workflow JSON

如果要运行当前已经接入的 multi-app `Switcher` app strip 回归，优先使用：

- `build-space-fixture-workflow.sh --workflow-config docs/fixtures/space-fixture-switcher-multi-app-workflow.json`
- 默认输出的 `resolved-workflow.json`，或通过 `FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH` 显式指定路径
- [FlowTabUITests+SpaceFixtureSwitcherMultiAppWorkflow.swift]({user-home}/Projeck-Works/Personal/FlowTabApp/FlowTabUITests/FlowTabUITests+SpaceFixtureSwitcherMultiAppWorkflow.swift)

如果要继续把更多 multi-app workflow 场景接到 FlowTab 真实 runtime end-to-end 测试，仍需要继续扩展这层测试驱动逻辑；当前已落地 `Home` 多 app 计数、窗口列表隔离、`fullscreen-only` 场景和 `Switcher` app strip 场景。

## 待接入清单（按代码现状）

以下清单按“当前代码真实接入情况”整理，指的是**尚未接入到 FlowTab 真实 runtime UI tests 的 multi-app workflow E2E 用例**，不包含已经由 unit、behavior、mock runtime 或 fixture app 自身 UI tests 覆盖的场景。

本轮已接入：

- `Switcher` app strip 在 multi-app workflow 下展示全部真实 app。
  场景：至少 3 个 app，使用不同 bundle identifier 和 appName。
  断言：打开 switcher 后，`flowtab.switcher.app.*` 覆盖 workflow 中全部 app，而不是只出现当前前台 app 或单一 fixture app。

当前优先级最高的是：

- `Switcher` window preview 在切换 app 后只展示当前 app 的窗口 cards。
  建议场景：每个 app 至少 2 个窗口，其中一个 app 含 tabbed window，另一个 app 含 fullscreen window。
  目标断言：进入 preview layer 后，`flowtab.switcher.window.*` 只对应当前选中 app 的窗口集合。

- window-scope search 在 multi-app workflow 下能检索真实窗口标题。
  建议场景：把默认搜索范围切到 `window`，让多个 app 分别提供 `Docs`、`Mail`、`Finder Main` 等标题。
  目标断言：搜索结果出现真实 `flowtab.switcher.search.window.*` 项，并能跨 app 找到目标窗口。

- tabbed window 的 selected tab title 能跨 app 正确进入 FlowTab UI。
  建议场景：Chrome fixture 使用原始窗口标题 `Chrome Window 1/2`，选中 tab 为 `Docs/Mail`，同时再启动至少一个非 tabbed app。
  目标断言：FlowTab 在 `Home` 或 `Switcher` 中显示的是 `Docs/Mail` 这类 resolved title，而不是原始 window title。

- 不同 app 拥有同名窗口时，window-scope search 仍能同时给出多条真实结果。
  建议场景：两个 app 都含标题为 `Docs` 的窗口。
  目标断言：搜索结果保留多个 `Docs` 命中项，并通过 app name 区分归属，而不是错误合并或只保留一条。

- 多个真实窗口在标题、尺寸、位置等可见属性完全相同时，FlowTab 仍保留独立窗口结果。
  建议场景：两个窗口使用相同 resolved title、相同 frame、相同 mode，可分布在两个 app 或同一 app 内。
  目标断言：`Switcher` preview、window-scope search，以及需要时的 `Home` 窗口列表中仍保留多条独立窗口记录，而不是被错误合并、去重或只保留一条。

建议的首批落地顺序：

1. `Switcher` preview 切换
2. window-scope search 的真实多 app 窗口结果
3. tabbed window selected title 的跨 app 展示
4. 标题、尺寸、位置等属性完全相同的窗口仍保留独立结果
5. 同名窗口标题下的 search 结果区分

## 当前结论

当前 `SPACE_FIXTURE_APP_WORKFLOW` 的实际状态可以概括为：

- 已实现一个模板 fixture app：`FlowTabSpaceFixture`
- 已实现单 app 多窗口与 fullscreen 路径
- 已实现 workflow 配置解析与应用内 tab 模型
- 已实现 workflow 级 app 变体构建脚本
- 已实现 fixture app 自身对 tabbed window 的 UI 覆盖
- 已实现基于 resolved workflow JSON 的 FlowTab multi-app `Home` 计数、app 切换窗口列表隔离、`fullscreen-only app` 稳定展示，以及 `Switcher` app strip E2E 用例
- 尚未把多 app workflow 全量接到 FlowTab 真实 runtime end-to-end UI workflow

因此，这份文档应按“当前实现说明”理解，而不是“未来设计提案”。
