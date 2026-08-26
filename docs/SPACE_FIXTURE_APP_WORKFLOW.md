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
- FlowTab 端到端真实 UI workflow 已开始消费 multi-app resolved workflow JSON，当前覆盖 `Home` 多 app 路径、`Switcher` app strip、preview 隔离和 window-scope search 激活路径；其余更细的 switcher/search 场景仍在逐步接入。

## 当前目标边界

`FlowTabSpaceFixture` 当前负责的是“制造受控的真实应用窗口拓扑”，不负责：

- 替代现有 unit、behavior、UI 主覆盖链路
- 作为稳定 CI 的唯一空间验证方案
- 复刻真实 Chrome、Finder、Notes 的全部交互逻辑
- 把测试专用逻辑混入 FlowTab 生产路径

## Target 与文件入口

当前相关实现主要分布在以下位置：

- [FlowTabSpaceFixture/FlowTabSpaceFixtureApp.swift](../FlowTabSpaceFixture/FlowTabSpaceFixtureApp.swift)
- [FlowTabSpaceFixture/SpaceFixtureAppDelegate.swift](../FlowTabSpaceFixture/SpaceFixtureAppDelegate.swift)
- [FlowTabSpaceFixture/SpaceFixtureLaunchConfiguration.swift](../FlowTabSpaceFixture/SpaceFixtureLaunchConfiguration.swift)
- [FlowTabSpaceFixture/SpaceFixtureWorkflowConfiguration.swift](../FlowTabSpaceFixture/SpaceFixtureWorkflowConfiguration.swift)
- [FlowTabSpaceFixture/SpaceFixtureWindowPlan.swift](../FlowTabSpaceFixture/SpaceFixtureWindowPlan.swift)
- [FlowTabSpaceFixture/SpaceFixtureWindowCoordinator.swift](../FlowTabSpaceFixture/SpaceFixtureWindowCoordinator.swift)
- [FlowTabSpaceFixture/SpaceFixtureWindowContentView.swift](../FlowTabSpaceFixture/SpaceFixtureWindowContentView.swift)
- [scripts/testing/build-space-fixture-app.sh](../scripts/testing/build-space-fixture-app.sh)
- [scripts/testing/build-space-fixture-workflow.sh](../scripts/testing/build-space-fixture-workflow.sh)

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

Workflow window 配置中，`publishesApplicationAXWindow` 控制该窗口是否进入 app-level
AX children 列表；`suppressesWindowAccessibilityExposure` 则进一步控制 host
`NSWindow` 自身是否作为 AX window 暴露。后者用于构造真实 CG/Space 可见、AX
直接窗口列表缺席的 `space-backed` runtime 输入，不应当用于普通业务窗口场景。

## 当前构建脚本

### `build-space-fixture-app.sh`

当前用途：

- 构建 `FlowTabSpaceFixture` 模板 app
- 复制一个 app bundle 变体
- 重写 `CFBundleDisplayName`
- 重写 `CFBundleIdentifier`
- 使用 ad-hoc 签名重新签名生成的变体

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

### 签名行为

fixture app 变体只是用于本地 UI 测试和手工回归的测试拓扑，不需要 Apple Development 或 Mac Development 证书。两个构建脚本都会在模板 app 的 `xcodebuild` 阶段禁用签名，然后在改写 app name 和 bundle id 后，对最终生成的变体执行 ad-hoc 重签。

这个流程的目标是：

- 避免 fixture 生成依赖本机是否安装了 `FLOWTAB_DEVELOPMENT_TEAM` 对应的私钥
- 保证修改过 `Info.plist` 的 app bundle 仍有一致的本地代码签名
- 让 fixture 变体保留测试用途的临时身份，而不是绑定到开发者账号

因此，`build-space-fixture-app.sh` 和 `build-space-fixture-workflow.sh` 的成功生成不应该要求本机存在 `Apple Development` identity。`Apple Development` 只用于下面提到的固定路径 `Flow Tab.app` / `Flow Tab UITest.app` 权限稳定性场景。

## 当前测试接入情况

### 运行真实环境 multi-app UI workflow 的本地前置条件

对于会真实拉起 `FlowTabSpaceFixture` app 变体并驱动 FlowTab 首页或 switcher 的 UI 用例，本地环境除了 fixture app 本身外，还需要满足以下条件：

- FlowTab 已授予 `Accessibility`
- FlowTab 已授予 `Screen & System Audio Recording`
- `Flow Tab.app` 与 `Flow Tab UITest.app` 使用互相兼容的 macOS designated requirement，而不是一份 `adhoc`、一份 `Apple Development`

这里要注意：

- macOS 隐私权限实际绑定的是 app 的 designated requirement，不是单纯绑定文件名，也不是只看 `TeamIdentifier`。
- `TeamIdentifier` 是 requirement 的重要组成部分，但不是完整身份。对于本仓库的 FlowTab app，稳定共享权限通常要求同一个 signing identifier（这里应是 `io.github.potato-dumplings.flowtab`）并由同一个 Apple Developer Team 签名。
- `Flow Tab UITest.app` 只是固定路径副本；文件名带 `UITest` 不代表它应该换一个 bundle/signing identifier。只要它和已安装的 `Flow Tab.app` 满足同一条隐私授权记录里的 requirement，macOS 才能复用权限。
- `CDHash` 不是 Apple Development 签名 app 是否共享权限的主要判据，正常重建后它可能变化。`CDHash` 只在判断 `adhoc` 或具体构建绑定时有辅助意义。
- 如果 `/Applications/Flow Tab.app` 仍然是 `adhoc`，而 UI tests 启动的是另一份 `Apple Development` 签名的 `Flow Tab UITest.app`，系统可能不会复用你已经授过的权限。

#### 首次运行前的权限获取流程（必须先做）

不要把第一次真实 workflow UI test 当成申请权限的入口。第一次运行应该只用于安装、启动并授权后续测试真正会启动的同一个 FlowTab 身份；确认权限稳定后，再跑 multi-app workflow。

1. 安装固定路径的 UI test app：

```bash
./scripts/testing/install-ui-test-app.sh
```

默认会安装到：

- `~/Applications/Flow Tab UITest.app`

脚本会使用 `FLOWTAB_DEVELOPMENT_TEAM`：如果当前 shell 没有导出它，就从 `xcconfigs/LocalSigning.xcconfig` 读取同名配置，并尝试使用匹配的本地 `Apple Development` identity 签名。需要临时覆盖 team 时，仍可使用：

```bash
./scripts/testing/install-ui-test-app.sh --development-team <TEAM_ID>
```

专用 `Flow Tab UITest.app` 安装成功后会签发一次性生命周期凭据。每次执行真实 workflow UI 用例前都重新安装；测试动作消费凭据，并在终态清理专用测试 app。

如果脚本输出的 codesign summary 显示 `Signature=adhoc` 或 `TeamIdentifier=not set`，不要继续把真实 workflow UI test 当成稳定权限验证。先安装带 Apple Development 签名的固定路径 app，或者明确接受每次重建后都需要重新授权这份 `adhoc` app。

2. 确认后续测试会启动哪个 app，并只给那一个身份授权。

默认情况下，`run-ui-tests-local.sh` 会校验本次安装凭据并启动：

- `~/Applications/Flow Tab UITest.app`

因此首次授权也应该打开这个路径：

```bash
open "$HOME/Applications/Flow Tab UITest.app"
```

如果你希望测试直接复用已经安装在 `/Applications` 里的 app，则先把同一份签名构建安装到该路径：

```bash
./scripts/testing/install-ui-test-app.sh \
  --install-path "/Applications/Flow Tab.app"
```

然后运行 UI test 时也显式使用同一个路径：

```bash
./scripts/testing/run-ui-tests-local.sh \
  --ui-test-app-path "/Applications/Flow Tab.app"
```

不要先给 `/Applications/Flow Tab.app` 授权，随后又让测试启动 `~/Applications/Flow Tab UITest.app` 的 `adhoc` 副本；这两者不一定满足同一条 TCC 授权 requirement。

3. 首次启动后，立即在系统设置里给这次实际启动的 FlowTab 授权：

- `系统设置 -> 隐私与安全性 -> 辅助功能`
- `系统设置 -> 隐私与安全性 -> 屏幕与系统音频录制`

可以通过 FlowTab 首页的权限引导或 Settings 里的权限入口打开系统设置。授权完成后，完全退出 FlowTab，再从同一个 app 路径重新打开一次；确认首页不再出现 `flowtab.home.permission.open-settings` / `flowtab.home.permission.dismiss` 权限引导按钮。

4. 确认权限已经授给正确身份后，再运行真实 workflow UI tests：

```bash
./scripts/testing/run-ui-tests-local.sh
```

该脚本当前会：

- 消费固定路径 `~/Applications/Flow Tab UITest.app` 的本次安装凭据
- 对本地 UI test 构建产物默认关闭代码签名，避免测试执行再次受 Xcode 当前签名配置影响
- 在成功、失败或可处理的中断终态结束专用测试 app 的精确进程身份并删除 bundle

测试结束后，`~/Applications/Flow Tab UITest.app` 应当已经消失。下一条 UI 测试命令从重新运行 `install-ui-test-app.sh` 开始。显式选择 `/Applications/Flow Tab.app` 时，正式应用会保留。

本机已验证过的成功路径：

```bash
./scripts/testing/install-ui-test-app.sh
codesign -dr - "$HOME/Applications/Flow Tab UITest.app"
codesign -dr - "/Applications/Flow Tab.app"
open -n "$HOME/Applications/Flow Tab UITest.app"
./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelWindowSearchActivatesFullscreenWorkflowWindowAcrossSpaces
```

成功获取或复用权限的判定信号不是整条 UI 用例必须通过，而是：

- `install-ui-test-app.sh` 输出本地 Apple Development 签名指纹，codesign summary 显示对应 TeamIdentifier。
- 两份 app 的 `codesign -dr -` 输出使用同一个 `identifier "io.github.potato-dumplings.flowtab"` 和同一条 Apple Development requirement；`CDHash` 可以不同。
- `run-ui-tests-local.sh` 输出的解析路径符合 `{user-home}/Applications/Flow Tab UITest.app` 路径意图。
- 子运行的 `status.json` 记录 `ui_test_app_cleanup_exit_code: 0` 与 `ui_test_app_removed: true`。
- 测试日志中 fixture app 已经启动并出现 `flowtab.spacefixture.workflow.ready` / `flowtab.spacefixture.window.mode.*`。
- FlowTab 打开后，`flowtab.home.permission.open-settings` 没有出现，测试继续进入 `flowtab.switcher.search.input` 或 `flowtab.switcher.search.window.*`。

如果后续失败点已经发生在 `Switcher`、search result 或 window activation 断言阶段，就说明权限门禁已经通过；这类失败应按对应 UI 用例或 XCUI snapshot 问题继续诊断，不要再归因到首次权限获取。

在 Codex 或其他受限沙盒里，`install-ui-test-app.sh` 可能先误报找不到本地 Apple Development identity，或被 SwiftPM 临时文件权限拦住。此时应在普通 Terminal 里重跑，或用允许访问本机 keychain / Xcode 临时目录的提权执行重跑；只有在非沙盒环境下仍找不到 identity，才把它判定为本机缺少签名证书。

如果之前已经给 `/Applications/Flow Tab.app` 授权，但真实环境 workflow 用例仍在首页看到权限引导按钮，优先检查的不是“有没有授权”，而是“本次启动的 `Flow Tab.app` / `Flow Tab UITest.app` 是否满足同一条 designated requirement”。

#### 权限门禁失败的判定

真实 multi-app workflow UI 用例有两个阶段：

- 先由 XCTest 拉起 `Finder Fixture`、`Chrome Fixture`、`Notes Fixture` 等真实 fixture app，并等待 `flowtab.spacefixture.workflow.ready`、`flowtab.spacefixture.workflow.summary`、`flowtab.spacefixture.window.mode.*` 等 fixture 可观测标记。
- 再启动被测 FlowTab，通过 FlowTab 真实 runtime 采样这些窗口，并进入 `Home`、`Switcher` 或 search 断言。

如果日志已经显示 fixture app 成功启动，甚至已经观测到 fullscreen 标记，例如 `flowtab.spacefixture.window.mode.2`，但随后 FlowTab 首页出现 `flowtab.home.permission.open-settings` / `flowtab.home.permission.dismiss` 权限引导按钮，则说明用例还没有跑到真正的 `Switcher`、search 或激活断言。此时失败点是仓库的权限门禁：当前环境没有给**本次被测的 FlowTab 实例**可用的 `Accessibility` 或 `Screen & System Audio Recording` 权限，或者权限记录里的 designated requirement 与本次启动的 app 不兼容。

不要把这种失败误判为新增 UI 用例、fixture workflow、fullscreen Space 激活逻辑或 search 逻辑失败。它只证明：

- 新增 UI 用例已经编译。
- XCTest 已经成功拉起真实 fixture app。
- 测试被 FlowTab 权限前置检查拦在激活断言之前。

即使用 `/Applications/Flow Tab.app` 跑，UI 前置权限仍失败，也仍然表示这台环境当前没有给被测 FlowTab 实例可用的 `Accessibility` / `Screen Recording` 权限；这不是“已经授权所以测试应该继续”的反证。

出现该情况时，先核对实际被测 app 路径和签名身份：

先重新运行 `install-ui-test-app.sh`，并在启动测试前执行以下检查；测试终态会自动删除专用测试 app。

```bash
codesign -dv --verbose=4 "$HOME/Applications/Flow Tab UITest.app"
codesign -dr - "$HOME/Applications/Flow Tab UITest.app"
codesign -dv --verbose=4 "/Applications/Flow Tab.app"
codesign -dr - "/Applications/Flow Tab.app"
```

重点比较：

- `Identifier`
- `TeamIdentifier`
- `Signature`
- `designated requirement`

如果两者都是 Apple Development 签名、`Identifier` 相同、`TeamIdentifier` 相同，并且 designated requirement 互相兼容，通常可以共享 `/Applications/Flow Tab.app` 已经获得的隐私权限；这时不要因为 `CDHash` 不同就直接判定不能共享。反过来，如果 `~/Applications/Flow Tab UITest.app` 是 `adhoc` / `TeamIdentifier=not set`，或者 `Identifier` / `TeamIdentifier` / designated requirement 不兼容，则 macOS 不会把其中一个 app 的隐私授权自动复用给另一个 app。处理方式是重新安装固定路径 UI test app，并给这次实际启动的 app 身份重新授予 `Accessibility` 和 `Screen & System Audio Recording`。

### 已接入的逻辑与行为测试

当前以下能力已经有自动化覆盖：

- workflow 配置解析
- tab 归一化
- fullscreen window 标记
- window planner 生成结果
- coordinator 对窗口显示和 fullscreen 调度的处理

对应测试主要在：

- [FlowTabTests+SpaceFixtureLaunchConfiguration.swift](../FlowTabTests/FlowTabTests+SpaceFixtureLaunchConfiguration.swift)
- [FlowTabTests+SpaceFixtureWindowCoordinator.swift](../FlowTabTests/FlowTabTests+SpaceFixtureWindowCoordinator.swift)

### 已接入的 fixture app UI 测试

当前 workflow 模式已经有 fixture app 自身的 UI 用例覆盖：

- [FlowTabUITests+SpaceFixtureWorkflowConfiguration.swift](../FlowTabUITests/FlowTabUITests+SpaceFixtureWorkflowConfiguration.swift)

该用例当前验证：

- workflow 文件能正确驱动 tabbed windows
- 当前选中 tab 会成为窗口标题
- 原始 window title 会作为 subtitle 保留
- tab strip 与 selected-tab 标识可被 XCTest 观测

### 已接入的 FlowTab multi-app 真实环境 UI 用例

当前已补上基于 resolved workflow JSON 的 multi-app `Home` 和 `Switcher` E2E 用例：

- [FlowTabUITests+SpaceFixtureMultiAppWorkflow.swift](../FlowTabUITests/FlowTabUITests+SpaceFixtureMultiAppWorkflow.swift)
- [space-fixture-home-multi-app-workflow.json](fixtures/space-fixture-home-multi-app-workflow.json)
- [space-fixture-home-fullscreen-only-workflow.json](fixtures/space-fixture-home-fullscreen-only-workflow.json)
- [FlowTabUITests+SpaceFixtureSwitcherMultiAppWorkflow.swift](../FlowTabUITests/FlowTabUITests+SpaceFixtureSwitcherMultiAppWorkflow.swift)
- [space-fixture-switcher-multi-app-workflow.json](fixtures/space-fixture-switcher-multi-app-workflow.json)
- [FlowTabUITests+SpaceFixtureEdgeInputsWorkflow.swift](../FlowTabUITests/FlowTabUITests+SpaceFixtureEdgeInputsWorkflow.swift)
- [space-fixture-switcher-edge-inputs-workflow.json](fixtures/space-fixture-switcher-edge-inputs-workflow.json)

这些用例当前验证：

- `Home` 页会同时展示多个 workflow app row
- `finder(1)`、`chrome(3, 含 1 个 fullscreen)`、`notes(1)` 的 `windowCount` 会分别显示为 `1w / 3w / 1w`
- `Home` 页切换不同 workflow app 后，窗口区只展示当前 app 的 resolved window titles，不混入其他 workflow app 的窗口标题
- `fullscreen-only` app 与普通 app 共存时，`Home` 页仍会展示该 app，且选中后仍能看到它的 resolved window title
- `Switcher` app strip 会同时暴露 workflow 中至少 3 个真实 app 的 `flowtab.switcher.app.*` accessibility anchors
- `Switcher` preview layer 会用真实 `flowtab.switcher.window.*` window card anchors 证明当前选中 app 的窗口隔离
- `Switcher` window-scope search 能检索普通窗口和 fullscreen/off-space 窗口，并在确认后激活目标 fixture window、收起 panel
- edge-input workflow 会在不启用 staggered layout 时证明同名、同尺寸、同位置窗口仍保留独立 preview 和 search 结果
- edge-input workflow 会证明非 ASCII、标点、空白和长标题能通过真实 AX/runtime search 并激活对应 fixture window
- workflow 模式下的 per-app 启动顺序、resolved window title 和 fullscreen 标记会被测试驱动层正确读取

该链路当前优先读取：

- `FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH`
- 默认输出路径 `./.build-local/space-fixture-workflow/variants/resolved-workflow.json`

### 当前仍主要使用单 app 路径的 FlowTab 真实环境用例

当前真实环境 FlowTab UI workflow 仍主要通过单 app 路径启动 fixture app，相关 helper 在：

- [FlowTabUITests+SpaceFixtureApp.swift](../FlowTabUITests/FlowTabUITests+SpaceFixtureApp.swift)
- [FlowTabUITests+SpaceFixtureWorkflow.swift](../FlowTabUITests/FlowTabUITests+SpaceFixtureWorkflow.swift)

当前这条链路使用的环境变量仍是：

- `FLOWTAB_SPACE_FIXTURE_APP_PATH`
- `FLOWTAB_SPACE_FIXTURE_BUNDLE_ID`

也就是说：

- 多 app workflow 构建和 per-app 启动能力已经实现
- FlowTab 真实 runtime end-to-end UI 用例已经开始消费 resolved workflow JSON，当前已覆盖 `Home` 多 app 计数、app 切换后的窗口列表隔离、`fullscreen-only app` 的稳定展示，以及 `Switcher` app strip、preview 隔离、window-scope search 激活
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
- [FlowTabUITests+SpaceFixtureMultiAppWorkflow.swift](../FlowTabUITests/FlowTabUITests+SpaceFixtureMultiAppWorkflow.swift)

其中：

- `space-fixture-home-multi-app-workflow.json` 直接对应默认生成的 `resolved-workflow.json`
- `space-fixture-home-fullscreen-only-workflow.json` 会在 UI 测试里复用同一批已构建的 fixture app 变体，并临时生成场景专用的 resolved workflow JSON

如果要运行当前已经接入的 multi-app `Switcher` app strip 回归，优先使用：

- `build-space-fixture-workflow.sh --workflow-config docs/fixtures/space-fixture-switcher-multi-app-workflow.json`
- 默认输出的 `resolved-workflow.json`，或通过 `FLOWTAB_SPACE_FIXTURE_WORKFLOW_PATH` 显式指定路径
- [FlowTabUITests+SpaceFixtureSwitcherMultiAppWorkflow.swift](../FlowTabUITests/FlowTabUITests+SpaceFixtureSwitcherMultiAppWorkflow.swift)

如果要继续把更多 multi-app workflow 场景接到 FlowTab 真实 runtime end-to-end 测试，仍需要继续扩展这层测试驱动逻辑；当前已落地 `Home` 多 app 计数、窗口列表隔离、`fullscreen-only` 场景，以及 `Switcher` app strip、preview 隔离、window-scope search 普通窗口和 fullscreen/off-space 激活场景。

## 待接入清单（按代码现状）

以下清单按“当前代码真实接入情况”整理，指的是**尚未接入到 FlowTab 真实 runtime UI tests 的 multi-app workflow E2E 用例**，不包含已经由 unit、behavior、mock runtime 或 fixture app 自身 UI tests 覆盖的场景。

本轮已接入：

- `Switcher` app strip 在 multi-app workflow 下展示全部真实 app。
  场景：至少 3 个 app，使用不同 bundle identifier 和 appName。
  断言：打开 switcher 后，`flowtab.switcher.app.*` 覆盖 workflow 中全部 app，而不是只出现当前前台 app 或单一 fixture app。
- `Switcher` window preview 使用真实 window card anchors 完成隔离断言。
  场景：每个 app 至少 2 个窗口，其中一个 app 含 tabbed window，另一个 app 含 fullscreen window。
  断言：进入 preview layer 后，真实 `flowtab.switcher.window.*` 只对应当前选中 app 的窗口集合；切换 app 后旧 app 的窗口 card anchor 不再可见。
- `Switcher` window-scope search 在 multi-app workflow 下检索真实窗口标题并确认激活目标窗口。
  场景：至少 3 个 app，Chrome 类 fixture 提供 tab-derived `Docs` window title。
  断言：search 默认范围切到 `window` 后，真实 `flowtab.switcher.search.window.*` 结果出现；确认结果后，目标 fixture window 成为 frontmost window。
- `Switcher` window-scope search 能从当前 Space 激活 fullscreen/off-space window。
  场景：一个 app 保持当前桌面窗口，一个 app 拥有 fullscreen window，另一个 app 处于普通窗口状态。
  断言：从当前 Space 打开 search 并选择 fullscreen window 后，macOS 切到目标 Space，目标 fixture window 成为 frontmost window，FlowTab panel 不残留。
- `Switcher` preview 和 window-scope search 在 edge-input workflow 下保留同名真实窗口。
  场景：不同 app 都含 `Shared Docs` 窗口，其中一个 app 内有两个标题、尺寸和位置都相同的 `Shared Docs` 标准窗口。
  断言：preview 保留两张同名独立 window card，window-scope search 保留 3 条同名独立结果，并用 app name 区分归属。
- `Switcher` window-scope search 在 edge-input workflow 下匹配并激活非 ASCII、标点、空白和长标题。
  场景：真实 fixture window 标题包含 `报告 Docs`、标点、空白和长标题后缀。
  断言：搜索能通过长标题中的标点词命中唯一真实窗口结果，确认后对应 fixture window id 成为 frontmost window。

### 未实现优先级清单

优先级按真实 runtime 风险排序：

- `P0`：当前已经能表达或部分验证，但还缺产品级真实 UI 断言的链路。
- `P1`：核心用户路径，mock/behavior 覆盖不足以证明真实 app、window、Space 激活。
- `P2`：重要回归边界，主要覆盖去重、刷新、标题归一化和测试基础设施可靠性。

1. `P1` app-scope search 在 multi-app workflow 下检索真实 appName/bundle identity 并激活目标 app。
   建议场景：至少 3 个 app 使用不同 appName 和 bundle identifier，查询命中非前台 app。
   目标断言：搜索结果出现真实 `flowtab.switcher.search.app.*` 项；确认结果后，对应 fixture app 成为 frontmost app。

2. `P1` `Home` 窗口列表点击真实窗口后激活对应 fixture window。
   建议场景：Home 已展示多个 workflow app，选中其中一个 app 后点击它的某个 resolved window title。
   目标断言：被点击的真实窗口成为 frontmost window；同 app 其他窗口和其他 app 的窗口不会被错误激活。

3. `P1` tabbed window 的 selected tab title 跨 app 进入 FlowTab 的 Home、Switcher 和 search。
   建议场景：Chrome fixture 使用原始窗口标题 `Chrome Window 1/2`，选中 tab 为 `Docs/Mail`，同时再启动至少一个非 tabbed app。
   目标断言：FlowTab 在 `Home`、`Switcher` preview 和 window-scope search 中显示的是 `Docs/Mail` 这类 resolved title，而不是原始 window title。

4. `P2` multi-app workflow 运行中 app/window 生命周期刷新不会留下 stale 结果。
    建议场景：启动多个 workflow app 后，退出其中一个 app，或关闭其中一个 fixture window，再重新打开 Home/Switcher/search。
    目标断言：已退出 app 和已关闭 window 从 `Home`、`Switcher` 和 search 结果中消失；仍存活的 app/window 不受影响。

5. `P2` 增加统一的 multi-app workflow 启动和清理入口。
    当前状态：`build-space-fixture-workflow.sh` 只生成 app 变体和 resolved workflow JSON，真实多 app 启动主要存在于 `FlowTabUITests` helper 内。
    目标能力：提供一个测试/本地回归可复用的启动与清理入口，按 `launchOrder` 拉起全部 fixture app，并在失败或测试结束时可靠终止所有 workflow app。

## 当前结论

当前 `SPACE_FIXTURE_APP_WORKFLOW` 的实际状态可以概括为：

- 已实现一个模板 fixture app：`FlowTabSpaceFixture`
- 已实现单 app 多窗口与 fullscreen 路径
- 已实现 workflow 配置解析与应用内 tab 模型
- 已实现 workflow 级 app 变体构建脚本
- 已实现 fixture app 自身对 tabbed window 的 UI 覆盖
- 已实现基于 resolved workflow JSON 的 FlowTab multi-app `Home` 计数、app 切换窗口列表隔离、`fullscreen-only app` 稳定展示，以及 `Switcher` app strip、preview 隔离、window-scope search 激活和 edge-input E2E 用例
- 尚未把多 app workflow 全量接到 FlowTab 真实 runtime end-to-end UI workflow

因此，这份文档应按“当前实现说明”理解，而不是“未来设计提案”。
