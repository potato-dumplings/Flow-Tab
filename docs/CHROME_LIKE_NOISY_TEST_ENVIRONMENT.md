# Chrome-Like Noisy Test Environment

## 当前目标

Chrome-like Noisy 环境用于复现 Chrome 在 full-screen Space 下给 FlowTab 带来的
窗口身份歧义：同一个 app 同时拥有 normal windows、full-screen tab surfaces、
full-screen host artifacts、以及多层 CG-only 或 AX-backed helper windows。

当前实现的目标不是让 fixture 失败，也不是精确复制 Chrome 的每一个私有窗口。
它要稳定证明三件事：

1. FlowTab 最终只暴露用户可切换的 4 个真实业务窗口。
2. 用户选择的每个窗口都带着正确的 title、CGWindowID、frame、Space 证据。
3. normal 和 full-screen 之间的切换通过通用窗口激活语义完成，并用目标
   CGWindowID 变为 onscreen 作为成功标准。

这份文档描述当前实现本身。真实 Chrome 日志仍然是背景依据，但不再把文档写成
“先让 Noisy 红，再修生产逻辑”的临时排查流程。

## 场景入口

同一套 Chrome-like topology 覆盖三个产品入口：

- Option+Tab global switcher window-state path。
- Window-scope search path。
- Control+Tab in-app window switcher path。

它们使用等价 workflow：

- `docs/fixtures/space-fixture-option-tab-window-state-noisy-cg-siblings-workflow.json`
- `docs/fixtures/space-fixture-window-search-noisy-cg-siblings-workflow.json`
- `docs/fixtures/space-fixture-control-tab-noisy-cg-siblings-workflow.json`

三个 workflow 的 app 形态相同：一个 `Chrome Fixture`
(`com.example.fixture.chrome`) 同时拥有 2 个 normal windows 和 2 个 full-screen
windows。

## 四个真实业务窗口

Noisy workflow 固定有 4 个用户可切换窗口：

| 窗口 | 标题 | 形态 |
| --- | --- | --- |
| normal1 | `Chrome Normal Tab` | standard desktop window |
| fullscreen1 | `Chrome Fullscreen Tab` | full-screen Space window |
| fullscreen2 | `Chrome Second Fullscreen Tab` | full-screen Space window |
| normal2 | `Chrome Incognito Tab` | standard desktop window |

Noisy siblings 可以让 CGWindowList 里出现更多窗口，例如 titlebar、toolbar、
omnibox、content wrapper、content plane、preview overlay、floating strip。
这些是 Chrome-like 噪声，不是最终用户可切换窗口。

正确的用户可见结果是：

```text
Chrome Fixture business windows: 4
normal windows: 2
full-screen windows: 2
user-visible switcher/search/in-app window entries: 4
```

如果 preview、search result、Home window list 或 in-app window switcher 里出现
`Chrome Fixture`、nil-title sibling、toolbar、omnibox、content wrapper，或窗口
条目数大于 4，说明 runtime mapping 没有把 Chrome-like 噪声收敛到正确边界。

## Fixture 组成

`AppKitSpaceFixtureWindow` 是每个业务窗口的 host。standard window 直接作为正常
业务窗口暴露；full-screen window 在进入 full-screen 前会根据计划创建 noisy
siblings。

full-screen host 的关键配置：

- workflow window 设置 `mode: "fullscreen"`。
- workflow window 设置 `noisyCGSiblings: true`。
- workflow window 设置 `publishesApplicationAXWindow: false`。
- host `ChromeLikeSpaceFixtureWindow` 在进入 full-screen 前调用
  `suppressAccessibilityExposure()`，让 app-level public AX 不把 host 当作直接可用
  的业务窗口。
- sibling windows 在 `toggleFullScreen` 前显示一次，并在 full-screen transition
  后延迟显示一次，使它们跟随 full-screen Space 的稳定形态。

这样做的效果是：CG 层能看到 Chrome-like full-screen topology，AX 层不会只给出
一个干净的 host window，让 FlowTab 必须做 CG/AX 对账和 artifact 过滤。

## Chrome-Like AX Provider 形态

Noisy full-screen target 会额外创建一组 sibling windows。当前实现中的 sibling
shape 是：

| suffix | title | bounds 语义 | AX 暴露 | cycle 行为 |
| --- | --- | --- | --- | --- |
| `titlebar` | app name | 顶部 37pt 条 | false | ignores cycle |
| `toolbar` | app name | titlebar 下方 41pt 条 | false | ignores cycle |
| `omnibox` | app name | toolbar 下方 80pt 条 | false | ignores cycle |
| `content-plane` | selected tab title | chrome stack 下方剩余内容区 | true | participates |
| `content-wrapper` | selected tab title | 中部 content-like 条 | false | participates |
| `preview-overlay` | nil | inset overlay | false | ignores cycle |
| `floating-strip` | nil | floating strip | false | ignores cycle |

`content-plane` 是当前 Chrome Fixture 的核心 AX-backed content surface。它使用真实
selected tab title，例如 `Chrome Fullscreen Tab`，并填满 chrome stack 下面的
剩余高度。host 自身被 suppress，titlebar/toolbar/omnibox 等 siblings 是 CG-only
噪声。

这个形态模拟的是 Chrome 中常见的现象：用户看到和选择的是 tab content surface，
但周围有同 pid、相似 title、相似 frame、相同 Space 的 helper CG windows。FlowTab
不能靠 “same pid plus title” 或 app activation 通过。

## Runtime Snapshot 收敛规则

当前 runtime mapping 的职责是把 noisy CG/AX 输入收敛为 4 个业务窗口。

主要规则：

- 收集 CGWindowList 原始 z-order，并为每个可用 CGWindowID 保留顺序信息。
- 通过 AX exact bridge、title、frame、Space topology、sticky binding 等信息绑定
  AX window 和 CG window。
- 对 full-screen host artifact 做过滤：如果同 title、同 geometry 或同 full-screen
  关系下已经存在 AX-backed content surface，就丢弃 host/container artifact。
- 对 desktop-space full-screen sibling surface 做降级排序：当真实 normal surface
  和 Chrome-like full-screen sibling 同时存在时，不让 desktop-space sibling 抢到
  presentation 第一位。
- 对同一 presentation class 内的窗口使用 CGWindowList z-order 作为 tie breaker，
  保留真实前后关系。

结果是：

- full-screen host wrapper 不进入用户可选条目。
- CG-only chrome stripes 不进入用户可选条目。
- AX-backed content-plane 代表对应 full-screen tab。
- normal desktop windows 保持可选，并且不会被 full-screen sibling 盖掉。

相关回归覆盖在 `FlowTabPriorityCoverageTests+RuntimeSnapshotAndPreview.swift`：

- `testRuntimeSnapshotProviderWindowListFiltersFullscreenSiblingArtifactsAroundNoisyWindows`
- `testRuntimeSnapshotProviderWindowListOrdersOnscreenWindowsByCGZOrderInFullscreenTopology`
- `testRuntimeSnapshotProviderWindowListKeepsDesktopFullscreenSiblingsBehindNormalSurfaces`

## Full-Screen 激活路线

FlowTab 不直接切 Space。full-screen 切换通过窗口激活语义完成。

当用户选择一个 full-screen tab 时，runtime context 中的目标窗口必须携带：

- `title`
- `cgWindowID`
- `activationHandleID` 或 AX window
- `spaceIDs`
- `frame`

`RuntimeActivator` 构造 `WindowFocusRequest` 后按可验证路线尝试 focus：

1. 使用目标 CGWindowID 走 `RuntimeCGWindowFocusBridge.focusWindow`。
2. 使用直接 AX window 或 live registry window 走 AX raise/main/focused。
3. 如果 public AX recovery 允许，扫描 public/remote AX windows，按 CGWindowID、
   title、frame 重新找 exact target。
4. 对 full-screen topology，必要时尝试 related AX surface、same-space CG
   surface、related CG surface。
5. 每次尝试后都用当前 CGWindowList 验证目标 CGWindowID 是否已经 `isOnscreen`。

成功标准不是 “app 被激活”，也不是 “Space ID 被设置”。成功标准是用户选择的
目标 CGWindowID 成为 onscreen，并且日志中 activation route 对应同一个
CGWindowID。

典型成功日志形态：

```text
window-request appID=com.example.fixture.chrome ... title=Chrome Fullscreen Tab cg=<target>
cg-window-focus accepted ... windowID=<target>
focus-attempt route=cg result=verified ... targetCG=<target>
focus-attempt route=ax-direct result=verified ... targetCG=<target>
```

不同机器和当前 Space 状态下，验证通过的第一条 route 可能不同。测试不要求逐字
固定某一条 route，但必须证明最终目标是同一个具体 CGWindowID。

## 当前窗口身份和窗口 recency

Control+Tab in-app window switcher 有一个额外问题：面板重新打开时，起点必须是
用户当前实际 focused 的窗口，而不是 presentation order 的第一个窗口。Option+Tab
也有相同的业务目标，但不能直接把当前真实 focused window 当成任意 app 的窗口态
起点；global app switcher 进入 window state 前，用户可能选的是另一个 app。

当前实现中，`LiveSwitcherModel.startFocusedAppWindowSession` 会：

1. 读取 frontmost app。
2. 读取该 app 的 `AXFocusedWindow`。
3. 优先用 focused AX window 的 CGWindowID 匹配 runtime window。
4. 如果 CGWindowID 不可用或不匹配，再用 title + frame 做唯一匹配。
5. 匹配成功时先调用 `SwitcherSession.selectWindow(appID:windowID:)`，再进入
   window cycle。
6. 匹配失败时才回退到原来的 window-cycle 起点。

这保证了 Noisy 场景里，即使 `Chrome Incognito Tab` 在 CG z-order 上排在前面，
从 `Chrome Normal Tab` 重新打开 Control+Tab 时，面板仍然从 `Chrome Normal Tab`
开始。

FlowTab 对用户可选择、可激活的窗口候选列表使用 app-local 的窗口 recency overlay。
这包括 Switcher 的 Option+Tab/Control+Tab 窗口态，也包括 Home 的窗口列表；原始
runtime snapshot 和诊断输出仍保留 runtime 自身的 presentation order，作为没有
可靠 recency 时的 fallback 证据。

1. FlowTab 成功激活某个具体窗口后，记录 app identity、stable window identity 和
   timestamp。
2. 打开 switcher 时，只刷新当前 frontmost app 里能精确匹配的 focused/runtime
   window。
3. snapshot 组装窗口列表时，只把该 app 自己的 recency overlay 到
   `WindowCandidate.lastActiveAt`。
4. 进入任意 app 的 window cycle 时，只看该 app 自己的窗口 recency；如果用户在
   global app switcher 里选择 B app，A app 的当前 focused window 不会污染 B app。
5. 没有可靠 recency 记录时，才回退到当前 runtime snapshot 的 presentation order。

相关回归覆盖在 `FlowTabPriorityCoverageTests+SessionAndPanelSearch.swift` 和
`FlowTabPriorityCoverageTests+WindowRecency.swift`，Home 的候选列表排序另由
`FlowTabTests+HomeWindowActivation.swift` 和
`FlowTabUITests+HomeAndLogs.swift` 覆盖：

- `testLiveSwitcherModelStartFocusedAppWindowSessionSelectsFocusedWindowIdentityOverWindowOrdering`
- `testLiveSwitcherModelGlobalSnapshotRecencyUsesOnlySelectedAppsOwnWindowEvidence`
- `testRuntimeWindowRecencyTrackerAppliesSameOrderingToHomeSnapshots`
- `testHomeRuntimeSnapshotServiceAppliesWindowRecencyToHomeCandidates`
- `testHomeWindowListUsesSeededWindowRecency`
- `testLiveSwitcherModelRecordsFrontmostRuntimeWindowWhenAXFocusedWindowUnavailable`
- `testRuntimeWindowRecencyTrackerOrdersRecordedWindowsBeforeFallbackInRecencyOrder`

## 必须证明的 Round Trip

Noisy 测试不只证明 “能从 full-screen 切到 normal” 或 “能从 normal 切到某个
full-screen”。当前 UI 回归要求 4 个业务窗口都能独立被选择并激活。

最小链路是：

```text
fullscreen1 -> normal1
normal1     -> fullscreen1
fullscreen1 -> normal2
normal2     -> fullscreen2
```

Option+Tab 的窗口态必须先从 global app switcher 选中目标 app，再进入该 app 的
window state，之后完成同一条链路。该入口的 Noisy 回归按阶段验证越来越长的
recency prefix：

```text
stage 1: fullscreen1
stage 2: normal1, fullscreen1
stage 3: fullscreen1, normal1, normal2
stage 4: normal2, fullscreen1, normal1, fullscreen2
```

每一步都必须验证：

- 面板里 exactly 4 个用户窗口 title。
- 当前 selected window 是上一步真实 focused 的窗口。
- Option+Tab window state 的已观测窗口 prefix 符合本阶段 recency 预期。
- 目标 selected item 的 title 符合本阶段目标。
- 目标 selected item 携带的 CGWindowID 属于该业务窗口。
- confirm 后 exact frontmost CGWindowID 等于刚才选择的 CGWindowID。

这条链路的意义是证明 4 个窗口都可切换，而不是证明 “full-screen 类型” 或
“normal 类型” 大体能切。

## 入口覆盖

当前 noisy topology 需要在三个入口下维持同一套 runtime truth：

- Option+Tab：global app/window switcher 必须看到同样的 4 个业务窗口，并能完成
  app 选择、进入 window state、四窗口 round trip 和分阶段 recency prefix 断言。
- Window search：window-scope search 结果必须绑定具体业务窗口，而不是 app row
  或 noisy sibling。
- Control+Tab：in-app focused-window session 必须从真实 focused window 开始，
  并完成四窗口链路。

对应 UI tests：

- `testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows`
- `testSwitcherPanelWindowSearchRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows`
- `testInAppWindowSwitcherControlTabRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows`

## 日志解释

调试 Noisy 场景时优先看这些日志：

- `window-entries app=Chrome Fixture ... entries=4`：snapshot 收敛是否正确。
- `filtered-fullscreen-host-artifacts`：host/container artifact 是否被过滤。
- `start in-app ... windows=4`：Control+Tab 面板是否进入 4 窗口 session。
- `advance key=tabForward`：用户导航是否在同一个 windowCycle 中推进。
- `window-request ... title=<target> cg=<target>`：activation target 是否是具体业务窗口。
- `focus-attempt route=... targetCG=<target>`：focus route 是否围绕同一目标。
- `visible=1` 或 `result=verified`：目标 CGWindowID 是否真的变为 onscreen。

旧排查阶段常见的 `ax=0`、`sticky=false`、`visible=0` 日志仍然有诊断价值，但它们
不再是当前成功实现的必要条件。当前 fixture 有 AX-backed `content-plane`，生产
逻辑也允许通过 verified CG/AX route 成功切到 full-screen target。

## 解决方案边界

Noisy 环境验证的是 FlowTab 自身的窗口身份识别、CG/AX 对账和 activation route。
以下路径不能作为产品修复，也不能作为测试通过的依据：

- 直接设置当前 Space，例如 `ManagedDisplaySetCurrentSpace`、managed display
  Spaces API、`CopyManagedDisplaySpaces`，或其他绕过用户窗口激活语义的 private
  Space switching。
- 依赖 Window menu / 视窗菜单切换，例如通过菜单项选择窗口或标签来替代 FlowTab
  自身的窗口身份、CG/AX 对账和 activation route 判断。

原因是这两类方案都绕过了核心问题。直接切 Space 只是在空间层面强行移动；Window
menu 只适用于部分 app 和部分菜单结构。它们不能证明 FlowTab 在 Chrome-like 噪声
下稳定识别并激活用户选择的具体 full-screen tab。

## 不算有效通过

下面这些结果都不算 Chrome-like Noisy 通过：

- 用户可见窗口条目不是 exactly 4。
- 选择的是 `Chrome Fixture` app row，而不是具体 tab window。
- full-screen host wrapper、toolbar、omnibox、nil-title overlay 出现在用户可选列表。
- 只判断 app frontmost，不判断 exact CGWindowID。
- 只覆盖一个 normal/full-screen 方向，没有证明 4 个窗口都可切。
- 使用 direct Space switching 或 Window menu 切换。
- Noisy fixture 在 FlowTab 采样前还没有进入 noisy full-screen topology。

## 验证命令

改动 fixture、runtime mapping、activation 或 Control+Tab 行为时，先跑相关
`FlowTabTests`：

```bash
./scripts/testing/run-flowtabtests-local.sh \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeSnapshotProviderWindowListFiltersFullscreenSiblingArtifactsAroundNoisyWindows \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeSnapshotProviderWindowListOrdersOnscreenWindowsByCGZOrderInFullscreenTopology \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testRuntimeSnapshotProviderWindowListKeepsDesktopFullscreenSiblingsBehindNormalSurfaces \
  -only-testing:FlowTabTests/FlowTabPriorityCoverageTests/testLiveSwitcherModelStartFocusedAppWindowSessionSelectsFocusedWindowIdentityOverWindowOrdering
```

再刷新固定路径 UI test app：

```bash
./scripts/testing/install-ui-test-app.sh
```

然后跑 Noisy UI 回归：

```bash
./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelOptionTabWindowStateRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows

./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testSwitcherPanelWindowSearchRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows

./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testInAppWindowSwitcherControlTabRoundTripsFullscreenWorkflowSiblingAcrossSpacesWithNoisyCGSiblingsWithoutAppAXWindows
```

文档-only 修改不需要跑 app tests；只需要检查本文件描述是否仍然和当前实现一致。

## Readiness Checklist

认为 Chrome-like Noisy coverage 有效前，至少确认：

- workflow 中同一个 app 同时包含 2 个 normal windows 和 2 个 full-screen windows。
- 两个 full-screen windows 都设置 `noisyCGSiblings: true`。
- 两个 full-screen windows 都设置 `publishesApplicationAXWindow: false`。
- full-screen host 在进入 full-screen 前 suppress 自身 AX exposure。
- `content-plane` 暴露 AX，并使用真实 selected tab title。
- titlebar、toolbar、omnibox、content-wrapper、preview-overlay、floating-strip 不作为
  用户窗口暴露。
- snapshot logs 中 `Chrome Fixture ... windows=4`。
- UI preview/search/in-app entries exactly 4。
- 每个阶段选择具体业务 title，不选择 app row。
- 每个阶段 confirm 后 exact frontmost CGWindowID 等于 selected window 的 CGWindowID。
- Control+Tab 重新打开时从当前 focused window identity 开始。
- activation logs 围绕同一个 target CGWindowID，并最终 verified。
- 没有引入 direct Space switching 或 Window menu route。
