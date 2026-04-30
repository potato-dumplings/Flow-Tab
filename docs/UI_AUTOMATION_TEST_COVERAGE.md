# UI 自动化测试覆盖清单（FlowTab）

更新时间：2026-04-30

## 目标与范围

- 目标：把 FlowTab 的可自动化 UI 主路径保持在可回归状态，并让每个 UI case 的覆盖意图、操作路径与断言点都能直接从文档读出来。
- 范围：`FlowTabUITests`、`FlowTabUITestsLaunchTests`。
- 说明：仅覆盖应用内可稳定自动化的交互；系统级跳转、Finder 打开目录等外部行为只验证入口是否存在，不把系统结果作为稳定断言。

## 覆盖总览（当前）

- 用例总数：39
- 覆盖域：启动导航、Home、权限提示、Logs、Settings、Switcher/Search、压测。
- 当前状态：应用内可稳定自动化的核心场景已有覆盖，Settings 搜索默认范围的双向运行时生效路径、Home 真实窗口点击激活路径、Switcher 真实 app-scope 搜索激活路径、Settings 中 `Command + Tab` 接管触发与退出恢复路径，以及真实 edge-input fixture 下的同名/同尺寸同位置窗口和非 ASCII 长标题路径已补齐，剩余真实 fixture 缺口按下方优先级继续补齐。
- 执行前提：大多数用例依赖 UI test launch arguments 控制权限状态、Mock Runtime、预置日志和重置偏好，以减少系统环境抖动。

## 用例详情（当前）

### 启动与导航

- `testLaunch`
  场景：使用默认启动方式执行一次启动冒烟。
  步骤：直接启动 `XCUIApplication()`，在首帧稳定后抓取当前窗口截图并附加到测试结果。
  验证：应用能正常启动，且能生成名为 `Launch Screen` 的截图附件。

- `testLaunchPerformance`
  场景：在重置用户偏好并关闭权限提醒横幅的前提下测量启动耗时。
  步骤：使用 `--flowtab-ui-reset-defaults` 和 `-showPermissionReminder NO` 启动应用，并通过 `XCTApplicationLaunchMetric` 统计启动性能。
  验证：应用可在测量周期内重复完成启动，不因首启提示或历史状态干扰性能数据。

- `testSidebarTabsSwitchContent`
  场景：权限已授权，验证侧边栏三大页签可稳定切换。
  步骤：启动后依次点击 `Home`、`Logs`、`Settings` 页签按钮。
  验证：每次点击后，对应内容容器 `home/logs/settings` 都会出现，确保导航与页面挂载链路正常。

### Home 与权限提示

- `testHomePermissionBannerHiddenWhenPermissionsGranted`
  场景：无障碍和录屏权限都被标记为已授权。
  步骤：启动应用后进入 `Home` 页面，检查权限横幅和“打开设置”按钮。
  验证：权限横幅不存在，权限入口按钮也不可点击，说明已授权状态不会误提示。

- `testPermissionReminderTogglePersistsAcrossRelaunch`
  场景：首启时权限未授权，需要从 Home 入口进入设置页关闭提醒。
  步骤：首次启动点击 Home 的“打开设置”，切换权限提醒开关；随后终止应用并在同样的未授权状态下重新启动。
  验证：重启后 Home 不再出现可点击的权限入口，说明“显示权限提醒”偏好已持久化。

- `testPermissionDismissPersistsAcrossRelaunch`
  场景：权限未授权，但用户选择在 Home 直接关闭当前权限提示。
  步骤：首次启动点击权限横幅上的关闭按钮，确认入口消失；随后终止并重新启动应用。
  验证：重启后 Home 仍不出现权限入口按钮，说明横幅关闭状态被正确记住。

- `testHomePageSelectingMockAppUpdatesWindowList`
  场景：使用 Mock Runtime，在 Home 页验证“应用列表 -> 窗口列表”的联动。
  步骤：启动后进入 `Home`，选中模拟应用 `Mock Browser`。
  验证：窗口列表中会出现 `mock-browser-docs` 对应的窗口行，说明首页应用选择会同步刷新窗口明细。

- `testHomePageClickingRealWorkflowWindowActivatesExactFixtureWindow`
  场景：真实 multi-app fixture workflow 中 Home 页面展示多个 app 和窗口。
  步骤：进入 `Home`，选择带有多个标准窗口的真实 fixture app，再点击其中一个非默认窗口行。
  验证：目标 fixture app 成为 frontmost app，且 frontmost CG window number 等于被点击 Home 窗口行暴露的真实 window id，证明不会误激活同 app 的其他窗口或其他 app 窗口。

### Logs

- `testLogsPageShowsSeededLogsAndClearRemovesOutput`
  场景：启动时预置 4 条不同级别日志，并把运行时日志级别设为 `debug`。
  步骤：进入 `Logs` 页面，检查四条带固定标记的日志是否渲染；随后点击“清空日志”按钮。
  验证：`debug/info/warn/error` 四条预置日志都存在且内容带指定 marker；清空后空状态提示出现。

- `testLogsPageRespectsRuntimeLogLevelVisibility`
  场景：同样预置四个级别的日志，但分别在 `DEBUG/INFO/WARN/ERROR` 四种运行时过滤级别下验证可见性。
  步骤：逐一启动对应日志级别场景，进入 `Logs` 页面检查每条日志行是否显示。
  验证：日志页面只展示不低于当前阈值的日志，低优先级日志会被隐藏。

- `testLogsOpenDirectoryButtonIsVisible`
  场景：有日志数据时，用户应能看到“打开日志目录”入口。
  步骤：预置 1 条日志后进入 `Logs` 页面。
  验证：`flowtab.logs.open-directory` 按钮存在，确保日志目录入口没有丢失。

### Settings - Appearance

- `testSettingsAppearanceTogglesCanBeChanged`
  场景：权限已授权，验证外观页两个布尔开关可交互。
  步骤：进入 `Settings`，找到“显示快捷键提示”和“在 Command-Tab 中显示”两个开关，并切换到与当前值相反的状态。
  验证：两个控件都存在，且切换后实际值与目标值一致。

- `testSettingsAppearanceThemeAndLanguagePersistAcrossRelaunch`
  场景：验证主题与语言设置的持久化。
  步骤：首次启动进入 `Settings`，把主题切到 `dark`、语言切到 `en`；终止后再次启动并回到设置页。
  验证：重启后主题仍为 `dark`，语言仍为 `en`，说明选择型偏好已正确写回。

- `testSettingsAppearanceThemeAndLanguageUpdateVisibleUI`
  场景：验证主题和语言设置会立即改变可见 UI，而不只是写入设置值。
  步骤：进入 `Settings`，先把主题切到 `light` 并读取设置页截图亮度，再切到 `dark`；随后把语言切到 `en`。
  验证：深色主题下设置页截图平均亮度显著低于浅色主题；语言切换后设置页出现英文标题与说明文案，中文说明文案消失。

### Settings - Window Behavior

- `testSettingsWindowBehaviorDelayAndTogglesPersistAcrossRelaunch`
  场景：验证窗口层自动进入延迟和相关开关的保存逻辑。
  步骤：首次启动进入 `Settings`，把自动进入延迟文本输入改为 `1.2345` 并提交，再切换“自动恢复最小化窗口”和“隐藏仅最小化应用”两个开关；随后重启应用。
  验证：延迟值会被归一化为以 `1.23` 开头的文本，两个布尔开关在重启后保持刚才的状态。

- `testSettingsWindowBehaviorHideMinimizedAppsAffectsSwitcherAppLayer`
  场景：验证“隐藏仅最小化应用”设置会真实影响 switcher 的 app layer。
  步骤：先用包含正常窗口应用和仅最小化窗口应用的 Mock Runtime 打开 switcher，确认两者默认都展示；随后进入 `Settings` 打开“隐藏仅最小化应用”，再重启并打开同一 switcher 场景。
  验证：正常窗口应用仍展示，仅最小化窗口应用不再出现在 switcher app layer，说明设置不只是持久化，已经影响用户可见运行时结果。

### Settings - Search

- `testSettingsSearchDisabledPreventsAutoSearchLaunchEntry`
  场景：用户关闭搜索功能后，即使通过 UI test 参数要求“启动即进入搜索”，也不应真正进入搜索态。
  步骤：首次启动在 `Settings` 关闭搜索开关；重启时注入 `--flowtab-ui-open-switcher-search` 并使用 Mock Runtime。
  验证：Switcher 面板会打开，但搜索输入框不存在，说明“禁用搜索”优先级高于自动进入搜索的启动参数。

- `testSettingsSearchDefaultScopePersistsAndShowsWindowThenAppResults`
  场景：验证搜索默认范围在 `window` 与 `app` 间切换后都会影响真实搜索结果。
  步骤：首次启动在 `Settings` 打开搜索功能，并把默认范围切到 `window`；重启后使用 Mock Runtime 打开标准 switcher，再按回车从用户路径进入搜索并输入窗口标题 `Inbox`；随后回到 `Settings` 把默认范围切回 `app`，再次从标准 switcher 进入搜索并输入 `Mail`。
  验证：`window` 阶段出现 `flowtab.switcher.search.window.window-com-flowtab-mock-mail-mock-mail-inbox` 窗口级结果，切回 `app` 后出现 `flowtab.switcher.search.app.com-flowtab-mock-mail` 应用级结果，说明该设置不只是持久化，已经双向影响搜索默认结果范围。

- `testSettingsSearchDefaultScopeCanSwitchBetweenAppAndWindow`
  场景：验证默认搜索范围控件本身可在 `app` 与 `window` 间切换。
  步骤：进入 `Settings` 并确保搜索已启用，然后先选 `app` 再选 `window`。
  验证：控件值会即时跟随变更，说明范围选择器可用且双向切换正常。

### Settings - Permission & Hotkey

- `testSettingsPermissionActionButtonsAreVisible`
  场景：权限未授权时，设置页应暴露两个权限处理入口。
  步骤：在无障碍和录屏权限均为未授权的前提下进入 `Settings`。
  验证：无障碍权限按钮和录屏权限按钮都存在。

- `testSettingsHotkeySelectionsPersistAcrossRelaunch`
  场景：验证主快捷键、退出键和 In-App 键位选择可持久化。
  步骤：首次启动进入 `Settings`，依次把主键改成 `space`、退出键改成 `z`、In-App 键改成 `a`；随后重启应用。
  验证：重启后三个下拉选择仍分别为 `space/z/a`。

- `testSettingsMainHotkeyRepresentativeMatrixTriggersSwitcher`
  场景：验证 Settings 中主快捷键的代表性 modifier/key 组合会真实触发 switcher。
  步骤：分别设置 `Option + Space`、Control + Grave、`Command + B`，每次设置后重新启动并按对应快捷键。
  验证：每个代表组合都会进入全局 switcher show 路径，覆盖 option/control/command 三类修饰键和空格、反引号、字母三类键位。

- `testSettingsCommandTabTakeoverTriggersSwitcherAndRestoresSystemShortcut`
  场景：用户在 Settings 中把主快捷键切到真实 `Command + Tab`。
  步骤：先把主键临时切到 `space`，再选择 `command` 修饰键与 `tab` 主键，等待系统 `Command + Tab / Command + Shift + Tab` 接管生效；随后按真实 `Command + Tab`，最后终止 FlowTab。
  验证：运行时日志出现接管成功和真实快捷键触发 switcher show 路径；takeover marker 在接管后为真，并在应用通过 `Command + Q` 正常退出后清回假，说明系统快捷键恢复成功。

- `testSettingsQuitHotkeyExplicitAndFallbackMatrixTerminatesSelectedApp`
  场景：验证 Settings 中退出快捷键显式配置和 `quit == main` fallback 后都能真实作用于当前选中 app。
  步骤：先设置 `Option + Z` 并按下退出当前选中 mock app；再设置主快捷键 `Option + Q` 且退出键也选择 `Q`，确认归一化为 `Option + W` 后按 fallback 快捷键。
  验证：两种路径都会发出 mock 终止请求，刷新后选中 app 从 switcher 中移除。

- `testSettingsInAppHotkeyExplicitAndFallbackMatrixStartsFocusedWindowSession`
  场景：验证 Settings 中 In-App 快捷键显式配置和 `inApp == main` conflict fallback 后都能真实进入 focused-window session。
  步骤：先设置 `Option + B` 作为 In-App 快捷键并触发；再设置主快捷键与 In-App 快捷键同为 `Option + B`，确认 In-App 归一化为 `Control + B` 后触发。
  验证：两种路径都会进入 In-App focused-window switcher 会话。

- `testSettingsHotkeyInAppControlsDisabledWithoutAccessibilityPermission`
  场景：无障碍权限缺失时，In-App 快捷键不应允许配置。
  步骤：在无障碍未授权、录屏已授权的前提下进入 `Settings`，定位 In-App 修饰键和主键控件。
  验证：两个控件都存在但处于禁用状态。

### Switcher / Search 面板

- `testSwitcherPanelShowsMockAppTilesInStandardMode`
  场景：用 Mock Runtime 打开 Switcher/Search 面板，并验证可以退回标准卡片模式。
  步骤：启动即进入搜索态，确认面板存在后按一次 `Escape`。
  验证：搜索输入框消失，说明面板能从搜索态退回到标准应用卡片模式。

- `testSearchPanelEntryAndResultActivation`
  场景：验证搜索输入、结果命中和回车激活整条链路。
  步骤：启动即进入搜索态，输入 `browser`，等待 `Mock Browser` 结果出现，然后按回车提交；若首次回车只结束输入法组合态，则补发一次回车。
  验证：搜索结果会出现，提交后 Switcher 面板最终消失，说明结果激活成功。

- `testSwitcherPanelAppSearchFindsAndActivatesRealWorkflowApp`
  场景：真实 multi-app fixture workflow 中使用 app scope 搜索 fixture app 的 bundle identity token。
  步骤：以 `app` 默认范围启动搜索态 switcher，输入目标 fixture app 的搜索 token，等待真实 `flowtab.switcher.search.app.*` 结果出现后按回车确认。
  验证：目标 fixture app 成为 frontmost app，证明真实 runtime 搜索结果可以按 app-scope 路径激活正确应用。

- `testSwitcherPanelPreviewKeepsIdenticalRealWorkflowWindowsDistinct`
  场景：真实 edge-input fixture workflow 中，同一个 app 拥有两个标题、尺寸和位置都相同的标准窗口。
  步骤：不启用 staggered layout 启动 edge workflow，打开标准 switcher，切到包含重复 `Shared Docs` 窗口的 fixture app 后进入 window preview layer。
  验证：preview 中出现两张独立 `flowtab.switcher.window.*` 卡片，标题 multiset 保留两条 `Shared Docs`，且 accessibility id 各不相同，说明真实窗口未被错误合并。

- `testSwitcherPanelWindowSearchKeepsDuplicateRealWorkflowTitlesDistinct`
  场景：真实 edge-input fixture workflow 中，不同 app 拥有同名窗口，且其中一个 app 内还有两个同名同位置窗口。
  步骤：以 `window` 默认范围启动搜索态 switcher，查询 `Shared Docs`。
  验证：搜索结果保留 3 条独立 `Shared Docs` 命中；其中 `Finder Fixture` 1 条、`Chrome Fixture` 2 条，且每条结果的 accessibility id 独立。

- `testSwitcherPanelWindowSearchMatchesAndActivatesRealWorkflowEdgeTitle`
  场景：真实 edge-input fixture workflow 中，窗口标题包含非 ASCII 字符、标点、空白和长标题文本。
  步骤：以 `window` 默认范围启动搜索态 switcher，查询 `punctuation` 并确认命中结果。
  验证：搜索能通过长标题中的标点词命中唯一真实窗口结果，确认选择后对应 fixture window id 成为 frontmost window。

- `testSearchPanelChineseQueryShowsChineseMockResult`
  场景：验证中文查询可命中中文模拟应用。
  步骤：启动即进入搜索态，输入中文字符 `测`。
  验证：搜索结果中出现 `com-xxx-test` 对应条目。

- `testSearchPanelPinyinInitialsShowChineseMockResult`
  场景：验证拼音首字母查询可命中中文应用。
  步骤：启动即进入搜索态，输入 `cs`。
  验证：结果中出现中文模拟应用 `com-xxx-test`。

- `testSearchPanelSharedCsQueryShowsCSGOAndChineseMockResults`
  场景：验证共享关键词查询可返回多条不同来源结果。
  步骤：启动即进入搜索态，输入 `cs`。
  验证：结果中同时出现 `com-xxx-csgo` 和 `com-xxx-test` 两条记录。

- `testSearchPanelSegmentedChineseQueryShowsCompoundMockResult`
  场景：验证中文复合词查询可命中分词索引结果。
  步骤：启动即进入搜索态，输入 `文件助手`。
  验证：结果中出现 `com-flowtab-mock-file-transfer-assistant` 对应条目。

- `testSearchPanelWrapFromLastResultScrollsBackToFirstResult`
  场景：验证搜索结果列表在选中项从最后一条回环到第一条时，会同步把视口滚回顶部附近。
  步骤：使用 `search-wrap` Mock Runtime 变体启动搜索面板，连续按下方向键直到命中最后一个结果 `Mock Wrap 10`，再额外按一次下方向键触发回环。
  验证：最后一项在回环前可见，回环后第一项 `com-flowtab-mock-wrap-01` 会重新变为可点击元素，说明选中态与列表滚动保持同步。

- `testSwitcherPanelMoveAppThenAutoEnterWindowLayerShowsMockWindows`
  场景：验证在标准 Switcher 模式中移动应用选择后，可自动切入窗口层。
  步骤：启动即进入搜索态后先按 `Escape` 回到标准模式，确认当前未展示 `Mock Mail` 的窗口列表，再按左方向键切换应用。
  验证：`mock-mail-inbox` 与 `mock-mail-draft` 两个窗口条目出现，说明移动应用选择后成功自动进入窗口层。

### 压测

- `testTabSwitchStressCPUAndMemory`
  场景：对 Tab 切换压测脚本做 CPU、内存和耗时基线观测。
  步骤：以 `--flowtab-tab-stress` 启动应用，持续 2 秒、每 16ms 触发一次切换，并通过 `XCTClockMetric`、`XCTCPUMetric`、`XCTMemoryMetric` 进行 3 轮测量。
  验证：应用能在压测窗口内正常启动并按预期自行退出，且性能指标可被持续采集。

## 未完成 / 待补覆盖

本节记录尚未进入上方“用例详情”的 UI 自动化与端到端缺口。跨层状态以 [TEST_COVERAGE_MATRIX.md](TEST_COVERAGE_MATRIX.md) 为准；当补齐任一条后，需要同步更新矩阵状态。

### P2

- 退出当前选中应用的完整 UI 快捷键路径
  场景：用户打开 switcher 后按配置的退出快捷键。
  目标断言：选中应用收到退出请求，面板刷新策略正确，且会话不会在进程真正退出前错误移除目标。

## 回归命令（示例）

优先使用仓库脚本，把 `DerivedData`、临时目录和缓存统一压到 `./.build-local/ui-tests`：

```bash
./scripts/testing/install-ui-test-app.sh
./scripts/testing/run-ui-tests-local.sh
```

如果已经准备好了固定路径的 UI test app，`run-ui-tests-local.sh` 会自动优先使用：

- `~/Applications/Flow Tab UITest.app`

也可以显式指定或关闭这条路径：

```bash
./scripts/testing/run-ui-tests-local.sh --ui-test-app-path ~/Applications/Flow\ Tab\ UITest.app
./scripts/testing/run-ui-tests-local.sh --no-ui-test-app
```

需要缩小到单个 UI 用例时：

```bash
./scripts/testing/run-ui-tests-local.sh \
  -only-testing:FlowTabUITests/FlowTabUITests/testHomePageSelectingMockAppUpdatesWindowList
```

如果仍需直接调用 `xcodebuild`，可参考下面的基础命令：

```bash
xcodebuild -project FlowTab.xcodeproj -scheme FlowTab \
  -destination 'platform=macOS' \
  -derivedDataPath ./.build-local/test-all \
  test -only-testing:FlowTabUITests
```
