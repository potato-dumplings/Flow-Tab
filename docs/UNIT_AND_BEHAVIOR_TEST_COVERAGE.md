# 单测与行为测试覆盖清单（FlowTab）

更新时间：2026-04-30

## 目标与范围

- 目标：把 Core 算法、应用层配置/权限/日志/搜索、以及关键行为链路的测试意图和断言结果沉淀成可回溯文档。
- 范围：`FlowTabCore/Tests/FlowTabCoreTests`、`FlowTabTests/*.swift`。
- 说明：本文件把“单测”和“行为测试”合并维护，格式与 UI 自动化清单一致，统一使用“场景 / 步骤 / 验证”描述。

## 覆盖总览（当前）

- 用例总数：256（按 `func test` 统计；`FlowTabCore` 33，`FlowTabTests` 223）
- 单测 / 行为测试：分层说明见下方用例来源与场景描述。
- 覆盖域：分组与会话状态机、偏好与热键归一化、权限与启动参数、运行时快照与激活、搜索索引与输入桥接、日志与语言、AppDelegate 启动链路、Switcher 面板交互、窗口预览与缓存。
- 当前状态：核心逻辑、配置持久化与主要行为回归路径均有对应测试说明，新增覆盖按主题放在同名 extension 文件中。

## 未完成 / 待补覆盖

本节记录尚未进入下方“用例详情”的单元测试与行为/集成测试缺口。跨层状态以 [TEST_COVERAGE_MATRIX.md](TEST_COVERAGE_MATRIX.md) 为准；当补齐任一条后，需要同步更新矩阵状态。

### 已补覆盖（2026-04-29）

- Settings 热键注册请求映射：新增 `HotkeyRegistrationRequest.normalized(...)` 共享 helper，并用表格用例覆盖正常值、非法值、主键与退出键冲突、In-App 与主快捷键冲突，以及持久化回写。
- 快捷键派生字段组合覆盖：新增组合表格测试，覆盖所有主修饰键类型、代表性主键、代表性退出键、forward/backward modifier、keyCode 与展示文案。
- Core session 到 `LiveSwitcherModel` 的代表性窗口层编排：新增行为测试，证明窗口层导航后的提交目标与 session commit 规则一致。
- Logs diagnostics 写入、读取、过滤和清空链路：新增 in-process 串联测试，覆盖 runtime log 写入、minimum level、since snapshot、noisy-category 过滤与 clear。

### 单元测试待补

- Home 列表投影规则
  场景：Home 页应用行、窗口数量文案、选中应用后的窗口列表投影仍主要由 UI 或 fixture workflow 间接证明。
  目标：若继续扩展 Home 展示规则，优先抽出 deterministic view model 或投影 helper，覆盖 app row、window count、空窗口、fullscreen-only、仅最小化窗口等输入形态。

- Runtime activation / recovery 纯决策规则
  场景：激活、恢复最小化、缺失窗口 fallback、retry recovery 的行为测试较强，但部分目标选择规则仍在带 fake runtime 的行为层证明。
  目标：当 target resolution 或 fallback 规则继续增长时，抽出纯决策 helper，补充目标窗口存在/缺失、最小化、当前进程、歧义候选和恢复策略的单元测试。

- Status item / app launch 决策规则
  场景：状态项打开窗口、恢复主窗口、fallback 到 Home scene 等路径主要由行为测试覆盖。
  目标：若状态项或启动路由继续扩展，抽出纯路由选择规则，覆盖已有窗口、无窗口、目标 tab、隐藏窗口恢复和场景打开 fallback。

### 行为 / 集成测试待补

- Settings appearance 传播链路
  场景：主题/语言有偏好与文案单测，也有 UI 持久化测试，但 in-process 的设置变更传播仍偏弱。
  目标：补充设置变更后 theme/language 状态、文案来源或通知链路被 App 内对象即时消费的行为测试。

- App launch / lifecycle / status item 组合路径
  场景：AppDelegate 启动/退出覆盖较强，status item open 也有代表性测试，但组合矩阵仍可更细。
  目标：在状态项或启动路由继续变化时，补充 open Home/Logs/Settings、已有窗口恢复、无窗口 fallback、权限提醒状态和 app visibility 偏好的组合行为测试。

- Pressure runner 编排
  场景：性能压测主要在 UI 或外部采样层证明，行为层只证明 stress runner 启动。
  目标：如果压测触发条件、参数选择、自动退出或采样记录逻辑继续复杂化，补充不依赖真实 UI 的 in-process 编排测试。

## 用例详情（当前）

### FlowTabCore / GroupingTests

来源：`FlowTabCore/Tests/FlowTabCoreTests/GroupingTests.swift`

- `testBuildGroupsPreservesFirstSeenGroupOrderAndAppOrderInsideGroup`
  场景：输入 3 个应用，其中 `dev` 组重复出现一次。
  步骤：调用 `Grouping.buildGroups` 按 `groupID` 构建分组。
  验证：分组顺序遵循首次出现顺序，组内应用顺序保持原始输入顺序。

- `testBuildGroupsNormalizesEmptyGroupIDToAppScopedGroup`
  场景：部分应用没有有效 `groupID`。
  步骤：把空 `groupID` 应用与正常分组应用一起传入 `Grouping.buildGroups`。
  验证：空 `groupID` 会被归一化为 `app:<bundleID>` 独立分组，不会错误合并。

- `testGroupIndexReturnsContainingGroupIndex`
  场景：已构建出多个分组，需要反查某个应用所在分组。
  步骤：调用 `Grouping.groupIndex(containing:groups:)` 查询不同应用。
  验证：返回值分别指向应用真实所在的 group 下标。

- `testGroupIndexReturnsZeroWhenAppDoesNotExist`
  场景：查询一个不存在于分组结果中的应用。
  步骤：对仅包含一个分组的结果调用 `groupIndex`。
  验证：未命中时回落为 `0`，避免下标越界。

- `testBuildGroupsReturnsEmptyWhenInputIsEmpty`
  场景：没有任何应用可分组。
  步骤：传入空数组调用 `Grouping.buildGroups`。
  验证：返回空结果，不构造无意义分组。

### FlowTabCore / PreferencesTests

来源：`FlowTabCore/Tests/FlowTabCoreTests/PreferencesTests.swift`

- `testDefaultPreferencesMatchExpectedValues`
  场景：直接读取 `SwitcherPreferences.default`。
  步骤：访问默认偏好对象，不注入自定义配置。
  验证：默认值与预期一致，包括自动恢复最小化窗口、`option-tab` 热键、允许接管 `Command + Tab`、最近活跃窗口策略、分组循环和跟随系统主题。

- `testHotkeyPresetsExposeExpectedKeysAndModifiers`
  场景：校验内置热键预设。
  步骤：读取 `Hotkey.commandTab` 和 `Hotkey.optionTab`。
  验证：两种预设分别暴露 `tab + command` 与 `tab + option`。

- `testKeyModifierSupportsComposedFlags`
  场景：组合修饰键需要支持位运算。
  步骤：创建 `[.command, .shift]` 组合标记。
  验证：组合结果同时包含两个修饰键，且原始位值等于两者按位或。

- `testThemeAndWindowStrategyExposeCompleteCaseSets`
  场景：主题与窗口切换策略的枚举必须完整暴露。
  步骤：读取 `ThemeMode.allCases` 和 `WindowSwitchingStrategy.allCases`。
  验证：主题包含 `light/dark/followSystem`，窗口策略包含 `recentActiveWindow/rememberLastSelectedWindow`。

### FlowTabCore / SwitcherSessionTests

来源：`FlowTabCore/Tests/FlowTabCoreTests/SwitcherSessionTests.swift`

- `testStartsFromSecondAppOnForwardTrigger`
  场景：以前进方向触发主切换器。
  步骤：使用示例应用数组初始化 `SwitcherSession`。
  验证：默认选中第二个应用，模拟 `Command + Tab` 的首轮前移行为。

- `testLeftRightCyclesAppsInAppCycle`
  场景：主切换器处于应用层循环模式。
  步骤：依次处理右箭头和左箭头输入。
  验证：应用选择会按预期在相邻应用间来回移动。

- `testUpThenLeftRightNavigatesGroups`
  场景：从应用层切入分组层后继续横向导航。
  步骤：先按上方向键进入 `groupCycle`，再左右切换。
  验证：会话模式变为分组层，左右导航会切换到对应组内首个应用。

- `testEnterWindowLayerAndTabCyclesWindows`
  场景：当前选中应用拥有多个窗口。
  步骤：进入窗口层后执行一次 `tabForward`。
  验证：模式切到 `windowCycle`，初始选中最近窗口，再按 Tab 可在窗口间轮转。

- `testEnterWindowLayerRequiresAtLeastTwoWindows`
  场景：当前应用只有一个窗口。
  步骤：在后退方向启动会话后尝试 `enterWindowCycleIfPossible`。
  验证：会话保持在应用层，不会为单窗口场景自动切入窗口层。

- `testForceEnterWindowLayerAllowsSingleWindow`
  场景：显式要求即使只有一个窗口也进入窗口层。
  步骤：调用 `enterWindowCycle(allowSingleWindow: true)`。
  验证：返回 `true`，并切换到针对该应用的窗口循环模式。

- `testUpInWindowLayerReturnsToAppCycle`
  场景：用户已从分组层进一步进入窗口层。
  步骤：在窗口层按上方向键。
  验证：会话会退回应用层，而不是停留在窗口层。

- `testDownInAppCycleEntersWindowLayerWhenPossible`
  场景：应用层当前选中项有多个窗口。
  步骤：在 `appCycle` 中按下方向键。
  验证：会话进入该应用的窗口层。

- `testDownInAppCycleDoesNotEnterWindowLayerWhenSingleWindow`
  场景：应用层当前选中项只有一个窗口。
  步骤：在 `appCycle` 中按下方向键。
  验证：会话保持在应用层，不做无效切换。

- `testSelectAppByIDSwitchesToAppCycle`
  场景：当前会话已在窗口层。
  步骤：调用 `selectApp(withID:)` 切换到另一个应用。
  验证：选择成功后会话回到应用层，并指向目标应用。

- `testSelectWindowByIDSwitchesToWindowCycle`
  场景：需要通过应用 ID 和窗口 ID 直接跳转到特定窗口。
  步骤：调用 `selectWindow(appID:windowID:)`。
  验证：会话切换到对应应用的窗口层，并选中指定窗口。

- `testCommitDoesNotRestoreMinimizedWindowWhenDisabled`
  场景：窗口恢复策略被显式关闭。
  步骤：构造关闭自动恢复最小化窗口的偏好并提交选择。
  验证：提交结果回退为应用激活目标，而不是带恢复标记的窗口目标。

- `testRemembersWindowAcrossSessions`
  场景：窗口切换策略为“记住上次选择窗口”。
  步骤：第一次会话在窗口层切换并提交；第二次会话注入第一次保存的 `rememberedWindowIDByAppID`。
  验证：第二次提交会直接命中上次记住的窗口，并在需要时带上恢复最小化标记。

### FlowTabCore / SwitcherSessionEdgeTests

来源：`FlowTabCore/Tests/FlowTabCoreTests/SwitcherSessionEdgeTests.swift`

- `testStartsFromLastAppOnBackwardTrigger`
  场景：以后退方向触发主切换器。
  步骤：用共享分组样例初始化会话。
  验证：默认选中最后一个应用，符合反向循环预期。

- `testAppCycleNavigationClampsAtEdgesWhenWrappingDisabled`
  场景：关闭分组/应用循环回绕。
  步骤：从末尾应用开始连续左右移动。
  验证：到达边界后会停在首尾，不会回绕。

- `testTabInGroupCycleMovesWithinCurrentGroup`
  场景：已进入分组层，当前组内有多个应用。
  步骤：先切入 `groupCycle`，再执行前后 Tab。
  验证：Tab 仅在当前组内移动，不跨组跳转。

- `testGroupCycleLeftRightChangesGroupsAndSelectsFirstAppInGroup`
  场景：分组层横向切换不同组。
  步骤：进入 `groupCycle` 后左右切组。
  验证：组索引会变化，且每次切组后自动指向该组首个应用。

- `testCommitSelectionReturnsAppWhenSelectedAppHasNoWindows`
  场景：目标应用没有任何窗口。
  步骤：构造只含空窗口应用的会话并提交。
  验证：提交结果为应用级激活目标，而不是窗口级目标。

- `testCommitInWindowCycleReturnsWindowAndStoresRememberedWindowID`
  场景：窗口层提交时需要同时记住窗口选择。
  步骤：强制进入窗口层并提交当前最小化窗口。
  验证：提交结果是窗口目标，且 `rememberedWindowIDByAppID` 被同步写入。

- `testRememberStrategyFallsBackToMostRecentWhenRememberedWindowIsMissing`
  场景：记忆策略命中的窗口已不存在。
  步骤：带着失效的 remembered window ID 启动会话并提交。
  验证：会自动回退到最近活跃窗口，而不是返回空结果。

- `testReleasePrimaryModifierReturnsActivationTarget`
  场景：用户松开主修饰键结束会话。
  步骤：构造单应用单窗口会话并调用 `releasePrimaryModifier()`。
  验证：返回最终激活目标，等价于正常提交。

- `testSelectionAPIsReturnFalseForUnknownIDs`
  场景：通过不存在的应用/窗口 ID 进行选择。
  步骤：依次调用 `selectApp` 和 `selectWindow`。
  验证：两个 API 都返回 `false`，且当前选择不被破坏。

- `testEmptySessionDoesNotProduceActivationTarget`
  场景：会话启动时没有可切换目标。
  步骤：对空会话调用导航、提交、释放修饰键与显式选择接口。
  验证：不会产生激活目标，也不会错误报告选择成功。

### FlowTab / 快捷键与启动参数单测

来源：`FlowTabTests/FlowTabTests.swift`、`FlowTabTests/FlowTabTests+HotkeyCoverageGaps.swift`

- `testResolveKeepsCommandWhenMainShortcutIsCommandTab`
  场景：主快捷键显式配置为 `Command + Tab`。
  步骤：调用 `SwitcherHotkeyPreferencesStore.resolve` 解析原始值。
  验证：主修饰键、主键和退出键均按输入保留，不发生意外降级。

- `testResolveFallsBackQuitKeyWhenQuitEqualsMainKey`
  场景：退出键和主快捷键冲突。
  步骤：将主键和退出键同时设为 `q` 再执行解析。
  验证：主键保留为 `q`，退出键自动回退到不冲突的 `w`。

- `testLoadPersistsNormalizedHotkeyValues`
  场景：`UserDefaults` 中保存了冲突或待归一化的热键值。
  步骤：写入隔离 suite 后调用 `load(userDefaults:)`。
  验证：返回配置被归一化，且回写后的持久化值也已修正。

- `testResolveFallsBackToDefaultValuesForInvalidHotkeyRawInputs`
  场景：热键原始值全部非法。
  步骤：传入无效修饰键、主键和退出键字符串进行解析。
  验证：解析结果完全回退到默认配置。

- `testRuntimeActivatorOpenConfigurationActivatesTargetApp`
  场景：检查运行时打开配置是否会激活目标应用。
  步骤：调用 `RuntimeActivator.makeOpenConfiguration()`。
  验证：配置中的 `activates` 为 `true`。

- `testRuntimeActivatorOpenConfigurationReusesRunningAppInstance`
  场景：运行时激活应复用已有实例。
  步骤：读取同一 `OpenConfiguration`。
  验证：`createsNewApplicationInstance` 为 `false`。

- `testHotkeyConfigurationDerivedFieldsAreConsistent`
  场景：从热键配置推导键码、修饰键掩码和展示文案。
  步骤：构造 `command + space` / `command + w` 配置。
  验证：前进/后退/退出的键码、修饰键位值和展示文本都一致且互相对应。

- `testHotkeyRegistrationRequestNormalizesRawSettingsValues`
  场景：Settings 中的原始热键选择需要归一化为统一注册请求。
  步骤：表格化输入正常值、非法值、主键与退出键冲突、In-App 与主快捷键冲突。
  验证：主热键、退出键和 In-App 热键都解析到预期配置，冲突场景自动回退到安全组合。

- `testHotkeyRegistrationRequestLoadPersistsNormalizedStoredValues`
  场景：持久化热键值已存在冲突或非法输入。
  步骤：写入隔离 defaults 后通过 `HotkeyRegistrationRequest.load(userDefaults:)` 读取。
  验证：返回配置被归一化，同时持久化值被修正为后续启动可直接读取的有效组合。

- `testHotkeyConfigurationDerivedFieldsCoverSupportedModifiersAndRepresentativeKeys`
  场景：热键派生字段需要覆盖所有支持修饰键和代表性键位。
  步骤：表格化构造 command/option/control 与 tab/space/grave/q/w 组合。
  验证：forward/backward/quit 的 modifier、keyCode 和展示文案保持一致。

- `testSwitcherEnumsExposeStableIdentifiersAndDistinctKeyCodes`
  场景：热键枚举需要稳定的 ID 与唯一键码。
  步骤：遍历全部修饰键和主键枚举。
  验证：枚举 `id` 等于 `rawValue`，所有键码唯一，且 `tab/space/grave` 对应 Carbon 常量正确。

- `testContentViewBodyBuildsWithPersistedPreferences`
  场景：界面构建需要读取用户持久化偏好。
  步骤：向 `UserDefaults.standard` 写入主题、热键和语言配置，再实例化 `ContentView` 与 `NSHostingView`。
  验证：SwiftUI 视图能成功构建，布局尺寸非零，`body` 描述非空。

- `testFlowTabTestLaunchOptionsParsesSwitcherAndSearchFlags`
  场景：解析 UI test 启动参数中的 Switcher/Search 标志。
  步骤：分别注入 `--flowtab-ui-open-switcher` 与 `--flowtab-ui-open-switcher-search`。
  验证：前者只打开 Switcher，后者同时标记“打开 Switcher + 进入搜索”。

- `testFlowTabTestLaunchOptionsParsesBooleanAndValueOverrides`
  场景：启动参数同时包含布尔开关和带值覆盖项。
  步骤：注入 Mock Runtime、重置 defaults、权限覆盖、预置日志数和运行时日志级别等参数。
  验证：每个布尔值与数值型覆盖项都被正确解析出来。

- `testFlowTabTestLaunchOptionsReturnsNilForInvalidOrMissingValues`
  场景：启动参数值缺失或格式错误。
  步骤：注入非法布尔值、缺少录屏权限参数值、非法日志数等数据。
  验证：对应覆盖项都会返回 `nil`，不会误判为合法值。

- `testSpaceFixtureLaunchConfigurationParsesTerminationDelay`
  场景：Space Fixture 需要通过启动参数模拟真实 app 延迟响应终止请求。
  步骤：注入 `--terminate-delay-ms 1200` 后解析 fixture 启动配置。
  验证：配置中的终止延迟毫秒数被正确记录，供 UI 自动化稳定观察退出前后的面板刷新行为。

- `testPermissionCheckersRespectLaunchOptionOverrides`
  场景：权限检查器在测试启动参数覆盖下工作。
  步骤：清空测试 override，再注入 `ax=false` 与 `screen=true` 启动参数。
  验证：无障碍权限查询和请求均返回 `false`，录屏权限查询和请求均返回 `true`。

### FlowTab / 运行时快照、激活与权限分支单测

来源：`FlowTabTests/FlowTabTests.swift`

- `testRuntimeProjectionRepairProviderUsesProjectionPayloadForUITestMockDatasetWhenLaunchFlagEnabled`
  场景：UI test 启动参数要求使用 Mock Runtime 数据集。
  步骤：注入 `--flowtab-ui-mock-runtime` 后读取 `RuntimeProjectionRepairProvider.fullRepairProjectionPayload()` 和 current-app projection payload。
  验证：projection payload 中的应用数量、首尾应用、窗口数、current-app summary 与上下文映射都与 Mock projection dataset 一致，不经过 legacy `snapshot()` 包装。

- `testAppInventoryServiceReadsUITestRuntimeProjectionDataset`
  场景：Settings app inventory 在 UI test mock runtime 下需要显示 projection seed 中的 mock apps。
  步骤：注入 `--flowtab-ui-mock-runtime` 后读取 `AppInventoryService.installedApps()`。
  验证：Mock Mail、Mock Browser 和文件传输助手来自 `FlowTabUITestRuntimeProjectionDataset`，保持 running/bundle/path metadata 稳定，不通过 provider-owned dataset API。

- `testRuntimeProjectionRepairProviderRealPathWithoutAccessibilityBuildsConsistentProjectionPayload`
  场景：真实运行路径下没有无障碍权限。
  步骤：关闭无障碍权限、开启“在 Command-Tab 中显示”和“隐藏最小化应用”，再读取 full-repair projection payload 与 app-window repair payload。
  验证：projection payload 会只保留应用层信息、窗口数组为空、上下文数量与应用数量一致，repair payload summary 也同步为零窗口。

- `testRuntimeActivatorRequestsActivationForAppTargetWhenNotCurrent`
  场景：激活目标应用不是当前进程。
  步骤：注入当前运行应用上下文并调用 `activate(target:.app)`。
  验证：会发起一次应用激活请求，且不传递额外 completion。

- `testRuntimeActivatorSkipsMissingContextsForAppAndWindowTargets`
  场景：激活目标在上下文映射中不存在。
  步骤：分别对缺失应用目标和缺失窗口目标执行激活。
  验证：既不会调用 `activateCurrentAppIfNeeded`，也不会发起请求激活。

- `testRuntimeActivatorFocusWindowPathReturnsWhenAXWindowsUnavailable`
  场景：窗口激活路径中没有可用的 AX 窗口信息。
  步骤：关闭无障碍权限，构造单窗口上下文后激活窗口目标。
  验证：仍会先激活应用，但不会再尝试额外的窗口聚焦操作。

- `testPermissionCheckersPreferTestingOverridesOverLaunchArgumentOverrides`
  场景：同时存在测试 override 和启动参数覆盖。
  步骤：将测试 override 与启动参数设置成相反结果后执行权限查询。
  验证：最终结果以测试 override 为准，而不是启动参数。

- `testScreenCapturePermissionRequestHonorsFalseLaunchOverride`
  场景：录屏权限请求被启动参数直接否决。
  步骤：在无测试 override 的情况下注入 `--flowtab-ui-screen-trusted false`。
  验证：`requestScreenCapturePermission()` 直接返回 `false`。

- `testScreenCapturePermissionRequestTestingOverrideCanForceFalse`
  场景：测试 override 需要强制把录屏权限请求置为失败。
  步骤：注入返回 `false` 的 request override，并同时设置启动参数为 `true`。
  验证：请求结果仍为 `false`，且 override 只被调用一次。

- `testScreenCapturePermissionResolutionHelperCoversOverrideLaunchAndLegacyPaths`
  场景：录屏权限解析工具需要覆盖测试 override、启动参数、旧系统兼容和真实系统查询四条路径。
  步骤：分别构造四种分支并调用 `resolvePermissionForTesting`。
  验证：优先级顺序正确，旧系统分支不会调用系统 provider，支持权限 API 时才落到系统查询。

### FlowTab / 面板窗口配置与搜索输入桥接单测

来源：`FlowTabTests/FlowTabTests.swift`

- `testSwitcherPanelWindowConfigurationSupportsFullscreenSpaces`
  场景：验证面板窗口默认配置适配全屏空间。
  步骤：读取 `collectionBehavior`、`styleMask` 和默认层级。
  验证：配置包含 `canJoinAllSpaces/fullScreenAuxiliary/ignoresCycle/stationary/canJoinAllApplications`，不包含 `moveToActiveSpace` 与 `transient`，并使用无标题非激活面板样式。

- `testSwitcherPanelWindowConfigurationElevatesLevelForFullscreenPresentation`
  场景：当前前台窗口位于全屏模式。
  步骤：分别请求普通场景和全屏场景的展示层级。
  验证：全屏场景层级高于普通 `.statusBar` 层级。

- `testSwitcherPanelWindowConfigurationElevatesLevelWhenFullscreenDetectionFallsBack`
  场景：全屏检测失败但需要回退抬升层级。
  步骤：调用 `presentationLevel(frontmostWindowIsFullScreen:false, requiresFallbackElevation:true)`。
  验证：返回层级高于默认值。

- `testSwitcherPanelWindowConfigurationAddsMoveToActiveSpaceOnlyForRecovery`
  场景：面板处于主动迁移到当前空间的恢复模式。
  步骤：对比默认展示行为和 `activeSpaceMove` 模式。
  验证：仅恢复模式包含 `moveToActiveSpace`，同时移除 `canJoinAllSpaces`，保留全屏辅助等必要标记。

- `testSwitcherPanelWindowConfigurationUsesNonActivatingBorderlessPanelStyle`
  场景：再次确认窗口样式不退化为普通标题窗口。
  步骤：读取 `styleMask`。
  验证：仅包含 `borderless` 和 `nonactivatingPanel`，不包含 `titled`、`resizable`。

- `testSearchSystemTextInputBridgeConfiguresVisiblePlainTextResponder`
  场景：搜索输入桥接层需要创建一个可见、单行、纯文本的 `NSTextView`。
  步骤：使用测试 harness 读取 text view 与 scroll view 配置。
  验证：背景透明、无富文本、无自动替换/纠错、单行剪裁、插入点颜色正确，并暴露 `flowtab.switcher.search.input` 无障碍标识。

- `testSearchSystemTextInputBridgeSynchronizeClampsQueryAndCursor`
  场景：外部状态同步到文本输入控件时，光标位置可能越界。
  步骤：先同步查询 `"wechat"` 且给出超大 cursor，再同步同一查询并给出负 cursor。
  验证：光标会被钳制到合法区间，插入点显隐随参数变化，且不会误发布输入变更。

- `testSearchSystemTextInputBridgePublishesQueryAndCursorFromTextInput`
  场景：用户在原生文本控件中输入和移动光标。
  步骤：先插入字符，再手动调整选区位置并触发变更通知。
  验证：桥接层会把最新 query 与 cursorPosition 反向发布给上层状态。

- `testSearchSystemTextInputBridgePreservesSelectAllAndDoesNotPublishCollapsedCursor`
  场景：用户执行全选操作，不应把它当作普通光标变更。
  步骤：同步文本后设置整段选区，再重新同步同一查询。
  验证：全选状态被保留，且不会向上层发布伪造的“折叠光标”位置。

- `testSearchSystemTextInputBridgeTracksMarkedTextCompositionLifecycle`
  场景：输入法组合态需要被显式跟踪。
  步骤：设置 marked text、触发文本变更，再执行 `unmarkText`。
  验证：组合态开始和结束都会被记录，query 同步正确，marked 状态会从 `true` 回到 `false`。

- `testSearchSystemTextInputBridgeDetachClearsMarkedStateAndIgnoresUntrackedViews`
  场景：桥接层只应响应自己管理的文本视图。
  步骤：先向未跟踪 `NSTextView` 发送变更通知，再卸载已跟踪文本视图。
  验证：未跟踪视图不会产生任何输入事件，detach 时会额外发布一次“marked state = false”清理信号。

### FlowTab / 终止流程、文案与偏好设置单测

来源：`FlowTabTests/FlowTabTests.swift`

- `testTerminateSelectedAppBehaviorKeepsAppUntilProcessActuallyExits`
  场景：切换器中触发“结束当前应用”后，进程尚未立即退出。
  步骤：对 `LiveSwitcherModel` 注入初始快照、延迟退出的进程探测结果和终止请求，再执行 `terminateSelectedApp()`。
  验证：终止期间应用先保留在会话中，等进程真正退出后才刷新布局并移除应用。

- `testTerminateSelectedAppUnitStopsPollingAfterTimeoutWhenAppStillRunning`
  场景：进程在轮询超时时间内始终未退出。
  步骤：注入一直返回“仍在运行”的进程检查结果并执行终止。
  验证：超时后不会触发布局刷新，应用仍保留在会话中，`terminatingAppID` 会被清空。

- `testTerminateSelectedAppUnitRefreshesOnWorkspaceTerminateAfterPollingTimeout`
  场景：轮询超时后由工作区终止通知补发最终刷新。
  步骤：先让进程检查始终返回“运行中”直到超时，再手动调用 `handleApplicationTerminated`。
  验证：超时阶段不刷新；收到终止事件后才重建布局并移除应用。

- `testAppLanguageResolveFallsBackToDefaultForUnknownRawValue`
  场景：语言原始值不合法。
  步骤：分别解析非法值与合法英文值。
  验证：非法值回退到简体中文，合法值保留为英文。

- `testAppLanguageLoadPersistsNormalizedValue`
  场景：`UserDefaults` 中保存了不支持的语言值。
  步骤：写入非法语言后调用 `AppLanguagePreferencesStore.load`。
  验证：返回默认语言，且持久化值也被改写为默认值。

- `testAppStringsReturnsLanguageSpecificTextAndAppliesReplacements`
  场景：多语言文案需要支持变量替换。
  步骤：分别以英文和简体中文读取 `homeAppWindowsOf`，并注入 `app` 占位符。
  验证：返回文本符合目标语言，并正确替换应用名；基础标签文案也能返回英文版 `Settings`。

- `testPermissionSettingsCardStateUsesDeniedCopyWhenPermissionsMissing`
  场景：权限卡片处于未授权态。
  步骤：构造 `showPermissionReminder = true` 且两个权限均为 `false` 的状态对象。
  验证：无障碍和录屏卡片都显示“未授权”描述和“请求权限”按钮文案。

- `testPermissionSettingsCardStateUsesGrantedCopyWhenPermissionsPresent`
  场景：权限卡片处于已授权态。
  步骤：构造提醒关闭且两个权限均为 `true` 的状态对象。
  验证：卡片文案切换为“已授权”描述与“关闭”按钮。

- `testRuntimeLogLevelOrderingUsesPriority`
  场景：运行时日志级别需要可比较。
  步骤：比较 `debug/info/warning/error` 四个枚举值。
  验证：优先级顺序满足 `debug < info < warning < error`。

- `testRuntimeLogPreferencesLoadPersistsDefaultForInvalidValue`
  场景：持久化日志级别值非法。
  步骤：向隔离 `UserDefaults` 写入未知级别并执行加载。
  验证：返回默认 `error` 级别，且回写后的持久化值被修正。

- `testThemePreferencesResolveFallsBackToFollowSystem`
  场景：主题原始值解析包含非法输入。
  步骤：分别解析合法 `light` 和非法字符串。
  验证：合法值保留，非法值回退为 `followSystem`。

- `testWindowLayerNormalizedAutoEnterDelayClampsAndRounds`
  场景：自动进入窗口层延迟值需要统一归一化。
  步骤：分别输入负数、小数、大数和 `infinity`。
  验证：结果会钳制到合法区间、保留两位小数，且无穷值回退默认值。

- `testWindowLayerSanitizeAutoEnterDelayTextNormalizesInputShape`
  场景：延迟输入框文本包含前导点、字母和多个小数点。
  步骤：调用 `sanitizeAutoEnterDelayText` 处理不同脏输入。
  验证：结果会被整理成合法数值字符串，例如 `.1299 -> 0.12`、`ab12.3.4cd -> 12.34`。

- `testWindowLayerSanitizeAutoEnterDelayTextClampsToMax`
  场景：输入框文本超出允许上限。
  步骤：传入 `"1000.999"`。
  验证：文本被限制为最大允许值 `999.99`。

- `testSearchInteractionDefaultsAndScopeNormalization`
  场景：搜索偏好默认值和范围配置回写。
  步骤：在隔离 `UserDefaults` 中读取默认启用状态，再关闭搜索并写入非法默认范围。
  验证：搜索默认启用；关闭后能读到 `false`；非法范围会回退到 `app` 并回写默认值。

- `testInAppWindowHotkeyResolveAndLoadNormalizeInvalidValues`
  场景：In-App 窗口快捷键原始值非法。
  步骤：先直接解析非法值，再把非法值写入 `UserDefaults` 执行加载。
  验证：修饰键回退为 `control`、主键回退为 `tab`、退出键保持 `q`，持久化值也同步被纠正。

- `testInAppWindowHotkeyResolveAvoidingMainConflictFallsBackToNonConflictingModifier`
  场景：In-App 快捷键与主快捷键完全冲突。
  步骤：构造主快捷键为 `control + tab`，再解析同样配置的 In-App 快捷键。
  验证：In-App 快捷键会回退到不冲突的修饰键组合。

- `testInAppWindowHotkeyResolveAvoidingMainConflictKeepsNonConflictingShortcut`
  场景：In-App 快捷键与主快捷键仅部分相同，但不冲突。
  步骤：主快捷键为 `option + tab`，In-App 快捷键设为 `option + space`。
  验证：解析结果保持原配置，不做多余改写。

- `testSwitcherBehaviorAndVisibilityPreferenceDefaults`
  场景：应用显示策略和切换器行为存在默认值与用户覆写。
  步骤：在隔离 `UserDefaults` 中读取默认“显示在 Command-Tab 中”和 `SwitcherPreferences`，再写入自定义恢复最小化窗口配置。
  验证：默认值正确，自定义值写入后会体现在读取结果中。

### FlowTab / 状态项、日志与搜索测试

来源：`FlowTabTests/FlowTabTests.swift`、`FlowTabTests/FlowTabPriorityCoverageTests+CoverageGaps.swift`

- `testStatusItemOpenActionUnhidesAndRestoresFirstRegularWindow`
  场景：状态栏“打开”操作需要优先恢复现有普通窗口。
  步骤：构造一个面板窗口和一个最小化普通窗口，再执行状态项打开动作。
  验证：应用会被激活并取消隐藏，普通窗口被反最小化并置前，面板窗口不受影响。

- `testStatusItemOpenActionOpensHomeSceneWhenNoRegularWindowExists`
  场景：应用当前只有面板窗口，没有普通窗口可恢复。
  步骤：执行状态项打开动作。
  验证：应用被激活，但不会尝试操作面板窗口，而是转为打开 Home 场景。

- `testAppWindowCoordinatorSkipsActivationWhenSwitcherPanelIsVisible`
  场景：Switcher 面板已在前台显示。
  步骤：构造一个可见的 Switcher 面板窗口和一个普通窗口后调用 `activateMainWindowOrOpenHomeScene`。
  验证：不会额外激活应用、取消隐藏或操作普通窗口，避免打断当前切换会话。

- `testRuntimeDiagnosticsReadRecentLinesAppliesMinimumLevelFilter`
  场景：读取近期日志时需要按最小级别过滤。
  步骤：写入 `info/warning/error` 三条带 marker 的日志，再以 `warning` 作为下限读取。
  验证：返回结果包含 `warning/error`，不包含 `info`。

- `testRuntimeDiagnosticsReadRecentLinesSinceSnapshotReturnsOnlyNewLines`
  场景：增量读取日志。
  步骤：先写一条旧日志并记录快照，再写两条新日志，最后带 `since` 参数读取。
  验证：结果只包含快照之后新增的日志行。

- `testRuntimeDiagnosticsReadRecentLinesHonorsLimitAndKeepsNewestEntries`
  场景：日志读取条数受上限限制。
  步骤：连续写入 5 条日志，再用 `limit = 2` 读取。
  验证：仅返回最新两条日志，顺序保持从旧到新。

- `testRuntimeLogNoisyCategorySuppressesInfoWhenVerboseDisabled`
  场景：嘈杂分类在关闭 verbose diagnostics 时应压制 `info`。
  步骤：关闭 verbose、设置最低日志级别为 `debug`，再写入 `InputTrace` 分类的 `info` 和 `warning`。
  验证：结果中只保留 `warning`，`info` 被抑制。

- `testRuntimeLogTypedNoisyCategorySuppressesDebugAndInfoWhenVerboseDisabled`
  场景：使用统一分类入口的 noisy 日志也要遵守 verbose 过滤。
  步骤：关闭 verbose、设置最低日志级别为 `debug`，再向 `Activation` 分类写入 `debug/info/warning/error`。
  验证：结果中只保留 `warning/error`，`debug/info` 被抑制。

- `testRuntimeLogNonNoisyCategoryAllowsInfoWhenMinimumLevelAllows`
  场景：普通分类不应被额外静音。
  步骤：同样关闭 verbose 并把最低级别设为 `debug`，再写入普通分类 `info` 日志。
  验证：读取结果中能看到该 `info` 日志。

- `testRuntimeLogPermissionWarningRecordsWithoutVerboseDiagnostics`
  场景：权限缺失类警告不应依赖 verbose diagnostics。
  步骤：关闭 verbose、设置最低日志级别为 `debug`，再向 `Permission` 分类写入 `warning`。
  验证：读取结果中能看到权限警告日志。

- `testRuntimeLogIntegrationFiltersDeltasAndClearsEntries`
  场景：运行时日志需要在同一链路中支持写入、过滤、增量读取和清空。
  步骤：记录初始快照，写入普通分类与 noisy 分类日志，分别按级别和 `since` 读取，再执行清空。
  验证：低级别日志和关闭 verbose 时的 noisy `info` 被过滤；增量读取只返回新日志；清空后 marker 不再出现。

- `testSearchMatchesAppByPartialName`
  场景：应用搜索支持部分名称命中。
  步骤：重建搜索索引、激活应用范围搜索并输入 `fari`。
  验证：结果精确命中 `Safari`。

- `testSearchMatchesCamelCaseAppBySegmentedWords`
  场景：驼峰式英文应用名支持按词分段检索。
  步骤：输入 `flow search`。
  验证：结果命中 `FlowTabSearch`。

- `testSearchQuerySupportsMiddleInsertionViaCursorMovement`
  场景：查询光标不在末尾时插入字符。
  步骤：先输入 `abcd`，将光标左移，再插入 `e`。
  验证：query 更新为 `abced`，光标位置同步更新到插入后位置。

- `testSearchDeleteBackwardRespectsCursorPosition`
  场景：退格删除应基于当前光标位置。
  步骤：先输入 `abced`，左移两位后执行一次删除。
  验证：query 变为 `abed`，光标停在删除后的正确位置。

- `testSearchAppendWhileResultsFocusedUsesQueryTail`
  场景：结果列表获得焦点时继续输入字符。
  步骤：输入 `abcd`、移动光标、切换结果焦点后追加 `e`。
  验证：追加行为会基于查询尾部处理，最终得到 `abcde`。

- `testSearchDeleteWhileResultsFocusedUsesQueryTail`
  场景：结果列表获得焦点时执行删除。
  步骤：输入 `abcd`、移动光标、切换结果焦点后执行退格。
  验证：删除逻辑基于尾部，最终 query 为 `abc`。

- `testSearchSelectionWrapsFromLastResultBackToFirstResult`
  场景：搜索结果列表支持从最后一条继续向下移动时回环到第一条。
  步骤：激活应用搜索并把焦点切到结果列表后，先向上移动到最后一条，再向下移动一次。
  验证：选中索引会从最后一项回到 `0`，对应结果文本从 `文件传输助手` 切换回 `微信`。

- `testSearchReplaceQueryWithoutRebuildUpdatesQueryAndCursor`
  场景：外部直接替换整个查询串且不触发重建。
  步骤：调用 `replaceQueryWithoutRebuild("微信", cursorPosition: 1)`。
  验证：query 与光标位置立即同步到新值。

- `testSearchMatchesChineseAppByPinyinInitialsAndFullSpelling`
  场景：中文应用同时支持拼音首字母和全拼匹配。
  步骤：先输入 `wx`，清空后再输入 `weixin`。
  验证：两次查询都能命中 `微信`。

- `testSearchMatchesChineseCompoundAppBySegmentedQueryWithoutSpaces`
  场景：中文复合词不带空格时也能按分词命中。
  步骤：输入 `文件助手`。
  验证：结果命中 `文件传输助手`。

- `testSearchMatchesEnglishAbbreviation`
  场景：英文缩写匹配。
  步骤：输入 `vsc`。
  验证：结果命中 `Visual Studio Code`。

- `testSearchMatchesByBundleIDButNotGenericComPrefix`
  场景：搜索可利用 bundle ID，但应忽略泛化前缀噪音。
  步骤：先输入 `wechat`，再清空并输入 `com`。
  验证：`wechat` 能命中 `微信`；仅输入泛化前缀 `com` 时不返回结果。

- `testSearchLocksChineseTestAppByPinyinInitials`
  场景：拼音首字母查询应稳定把目标中文应用置顶并选中。
  步骤：连续输入 `c`、`s`。
  验证：首个结果和当前选中结果都锁定为应用 `测试`。

- `testSearchLocksChineseTestAppByBundleIDPrefixes`
  场景：随着查询从 `t` 扩展到 `test`，bundle ID 前缀匹配应稳定收敛到同一应用。
  步骤：先输入 `t`，再依次追加 `e/s/t` 并在每步后重建结果。
  验证：从 `te` 开始目标应用 `测试` 会持续保持第一结果和当前选中项。

- `testSearchQueryCsMatchesBothCSGOAndChineseTestApp`
  场景：一个短查询同时命中英文缩写与中文拼音首字母。
  步骤：输入 `cs`。
  验证：结果集合同时包含 `CSGO` 和 `测试`。

- `testSearchRecoversResultsWhenIncrementalCandidateCacheMisses`
  场景：增量候选缓存漏掉潜在命中。
  步骤：先输入 `t` 再输入 `e`，触发从增量缓存回退到全量扫描。
  验证：第二步查询能恢复出之前未出现在缓存中的 `终端` 结果。

- `testWindowSearchCanMatchByAppNamePinyinInitials`
  场景：窗口级搜索也能利用所属应用的拼音索引。
  步骤：切换到窗口搜索范围并输入 `wx`。
  验证：结果中的 `secondaryText` 都显示为 `微信`。

- `testWindowSearchMatchesCamelCaseTitleBySegmentedWords`
  场景：窗口标题支持驼峰和分词匹配。
  步骤：在窗口范围输入 `search coordinator`。
  验证：结果命中 `FlowTab - SwitcherSearchCoordinator.swift`。

- `testSearchPerformanceWindowScope`
  场景：评估大规模窗口数据集下的搜索构建与查询耗时。
  步骤：生成 400 个应用、每个 25 个窗口的数据集，执行建索引与多轮基准查询。
  验证：性能日志能打印构建时长、查询时长和吞吐量，且探针查询 `weixin` 非空。

- `testSearchPressureWindowScopeUnified`
  场景：对统一查询集做窗口搜索压力测试。
  步骤：在同规模数据集上重复执行建索引与多轮查询。
  验证：会输出统一压测指标，并保证探针查询结果非空。

- `testSearchPressureWindowScopeSegmentedQueries`
  场景：对分词型查询集做窗口搜索压力测试。
  步骤：使用分词查询集合重复执行建索引和查询。
  验证：`flow search` 与 `文件助手` 两个探针查询都能返回结果。

### FlowTabPriorityCoverage / LiveSwitcherModel 与会话状态行为测试

来源：`FlowTabTests/FlowTabPriorityCoverageTests*.swift`

- `testLiveSwitcherModelStartSessionLoadsSnapshotAndCommitActivatesPreferredTarget`
  场景：启动切换会话后直接提交当前选择。
  步骤：注入带 3 个应用的运行时快照，启动前进方向会话后执行 `commitSelection()`。
  验证：会话加载出正确的应用数量与默认选中项，提交后清空会话状态，并向激活器发送预期窗口目标。

- `testLiveSwitcherModelCancelSelectionResetsSessionAndSearchState`
  场景：已进入搜索态时取消选择。
  步骤：启用搜索、启动会话并进入搜索模式后调用 `cancelSelection()`。
  验证：会话被清空，搜索态与搜索视图状态都回到初始值，面板风格恢复默认。

- `testLiveSwitcherModelEnterSearchModeAndApplySelectedAppResult`
  场景：应用范围搜索命中某个应用并把结果回填到切换会话。
  步骤：启用应用范围搜索，进入搜索态后移动选中项，再调用 `applySelectedSearchResultToSession()`。
  验证：搜索态退出，当前选中应用切换到目标应用，并回到应用层循环模式。

- `testLiveSwitcherModelApplySelectedWindowSearchResultEntersWindowCycle`
  场景：窗口范围搜索命中某个具体窗口。
  步骤：启用窗口范围搜索，移动到窗口级结果后应用该结果。
  验证：搜索态退出，会话进入对应应用的窗口层，并选中目标窗口。

- `testLiveSwitcherModelWindowLayerNavigationCommitsSessionWindowTarget`
  场景：`LiveSwitcherModel` 的窗口层导航应沿用 `SwitcherSession` 的窗口提交规则。
  步骤：注入带多窗口应用的运行时快照，启动会话后进入窗口层，切换窗口并提交。
  验证：提交目标为当前窗口层选中的窗口，激活器收到的目标与 session 状态一致。

- `testLiveSwitcherModelStartFocusedAppWindowSessionUsesFrontmostAppSnapshot`
  场景：从前台应用直接发起 In-App 窗口会话。
  步骤：把当前进程伪装成前台应用，注入带两个窗口的快照后启动 focused app window session。
  验证：面板样式变为仅窗口层，预览数量正确，会话模式直接进入当前应用的窗口循环。

- `testLiveSwitcherModelAutoEnterWindowLayerSuppressesImmediateReentryAfterManualExit`
  场景：自动进入窗口层后，用户手动退回应用层。
  步骤：启动会话并自动切入窗口层，再通过上方向键手动退出。
  验证：会话回到应用层后会暂时禁止再次自动进入，避免立即反复跳回窗口层。

- `testLiveSwitcherModelHandleApplicationTerminatedRefreshesSessionAndKeepsPreferredNextSelection`
  场景：当前会话中的应用被系统终止。
  步骤：用两份快照模拟“终止前/终止后”状态，并触发 `handleApplicationTerminated`。
  验证：会话会重建布局，应用数量减少，并自动选择合理的下一个候选应用。

- `testLiveSwitcherModelHandleApplicationTerminatedPreservesSearchStateDuringRefresh`
  场景：搜索态中发生应用终止。
  步骤：进入搜索态并输入查询后触发应用终止刷新。
  验证：刷新后搜索仍保持激活，查询文本和作用域不丢失，结果集会按新快照重算。

- `testLiveSwitcherModelHandleApplicationTerminatedIgnoresUntrackedApp`
  场景：终止通知来自不在当前会话中的应用。
  步骤：启动会话后传入无关应用 ID。
  验证：不会触发快照刷新，当前选择与应用数量保持不变。

- `testLiveSwitcherModelWindowPreviewUsesCaptureCacheAcrossReads`
  场景：窗口预览读取应复用缓存，避免重复抓图。
  步骤：启动 focused app window session，注入带颜色区分的抓图 override，连续两次读取窗口预览快照。
  验证：每个窗口只抓取一次即可在后续读取中复用，标题栏样式推断也会保留。

### FlowTabPriorityCoverage / Takeover、Hotkey Monitor 与 MRU 行为测试

来源：`FlowTabTests/FlowTabPriorityCoverageTests.swift`

- `testCommandTabTakeoverControllerReconcileActivatesAndRestoreReenablesSystemShortcuts`
  场景：接管 `Command + Tab` 后再恢复系统快捷键。
  步骤：创建隔离 `UserDefaults`，先执行 `reconcileIfNeeded(shouldTakeOver: true)`，再调用 `restoreSystemShortcutsIfNeeded()`。
  验证：系统热键 1/2 会先被禁用后被重新启用，同时 takeover marker 的写入与清除都正确发生。

- `testCommandTabTakeoverControllerReconcileRecoversFromAbnormalExitOnlyOnce`
  场景：上次退出异常，marker 留在持久化存储中。
  步骤：预先写入 marker，然后连续两次执行 `reconcileIfNeeded(shouldTakeOver: false)`。
  验证：第一次会主动恢复系统快捷键并清除 marker；第二次因状态已恢复而不再重复执行。

- `testCommandTabTakeoverControllerReconcileFailureRollsBackAndClearsMarker`
  场景：禁用系统快捷键过程中发生失败。
  步骤：注入一个在关闭第一个热键时返回错误的 setter，再尝试接管。
  验证：控制器会执行回滚，把已经动过的热键重新启用，并确保 marker 不残留。

- `testCommandTabTakeoverControllerSymbolicHotKeyResolverIsStableAcrossLookups`
  场景：符号热键 setter 的解析结果应稳定可缓存。
  步骤：对同一控制器连续查询两次测试入口。
  验证：两次结果完全一致。

- `testAppWindowCoordinatorOpenMethodsSelectRequestedTabBeforeActivation`
  场景：通过协调器打开 Home、Logs、Settings 时，需要先切换 tab 再激活窗口。
  步骤：依次调用 `openHome/openLogs/openSettings`，并记录激活时的当前 tab。
  验证：每次激活前 `HomeTabState.shared.selectedTab` 已经切换到目标页签。

- `testOptionTabHotkeyMonitorRoutesForwardAndBackwardPressReleaseCallbacks`
  场景：`Option + Tab` 热键监视器要把前进/后退的按下与松开事件路由给正确回调。
  步骤：手动分发前进和后退的按下/松开事件。
  验证：回调顺序依次为 `press-forward`、`release-forward`、`press-backward`、`release-backward`。

- `testOptionTabHotkeyMonitorPassesThroughUnrelatedEvents`
  场景：无关签名或无关 ID 的事件不应被误消费。
  步骤：向监视器分发错误签名和未知 ID 的事件。
  验证：返回 `eventNotHandledErr`，且任何回调都不会执行。

- `testOptionTabHotkeyMonitorParsesRawCarbonEvents`
  场景：原始 Carbon 事件存在多种异常和正确分支。
  步骤：依次构造“不支持的 kind”“缺失 payload”“错误签名”“合法前进按下”“合法后退松开”等事件。
  验证：只有合法热键事件被处理并触发正确回调，其余事件全部返回未处理。

- `testSystemAppMRUTrackerRankingPrefersTrackedOrderThenFallbackAndCurrentAppLaunchRank`
  场景：应用 MRU 排序需要综合跟踪顺序、回退顺序和当前应用的启动排名。
  步骤：调用 `SystemAppMRUTracker.rankByPID` 传入多套排名信息。
  验证：排序优先使用 tracked order，再回退到 fallback rank，并把当前应用放在最后。

- `testSystemAppMRUTrackerHelpersCoverNotificationRemovalAndPruningPaths`
  场景：MRU 跟踪器要处理重复激活、移除和裁剪无效 PID。
  步骤：连续记录激活、移除某个 PID、处理空通知和当前进程通知。
  验证：MRU 队列会去重、按需要删除终止进程，并忽略当前进程。

- `testSystemAppMRUTrackerRankingFallsBackWhenCurrentPIDLaunchRankIsMissing`
  场景：当前 PID 没有启动顺序排名。
  步骤：只提供 fallback rank 后执行 `rankByPID`。
  验证：仍能得到稳定排名，且当前应用会排在回退排名之后。

- `testSystemAppMRUTrackerObserversProcessWorkspaceActivationAndTerminationNotifications`
  场景：MRU 跟踪器监听工作区激活和终止通知。
  步骤：找到一个当前机器上真实存在的其他应用，发布激活通知和终止通知。
  验证：激活后 MRU 队列包含该 PID，终止后被移除。

- `testOptionTabHotkeyMonitorSkipsHotkeyRegistrationWhenHandlerInstallFails`
  场景：事件处理器安装失败时，不应继续注册热键。
  步骤：注入返回 `false` 的 handler installer，并开启监视器。
  验证：不会调用热键注册逻辑，且事件处理器安装标记保持为 `false`。

- `testOptionTabHotkeyMonitorStopUnregistersOnlySuccessfullyRegisteredHotkeys`
  场景：两个热键中只有一个注册成功。
  步骤：开启监视器后执行 `stop()`。
  验证：只会注销真正注册成功的热键，并移除事件处理器。

- `testOptionTabHotkeyMonitorRegistrationFailureLogsError`
  场景：热键注册最终失败应按 `error` 级别记录。
  步骤：注入总是失败的热键注册器并开启监视器，再按 `error` 下限读取运行时日志。
  验证：前进和后退两个热键注册失败都会出现在 `[ERROR] [HotKey]` 日志中。

### FlowTabPriorityCoverage / AppDelegate 启动与热键注册行为测试

来源：`FlowTabTests/FlowTabPriorityCoverageTests.swift`

- `testFlowTabAppInitStartsMRUTracking`
  场景：应用对象初始化时即启动 MRU 跟踪。
  步骤：把全局 tracker 替换为 spy 后实例化 `FlowTabApp`。
  验证：`startIfNeeded()` 被调用一次。

- `testAppDelegateLaunchInstallsObserversPromptsAccessibilityAndStartsStressRunner`
  场景：应用正常启动，需要完成观察者安装、无障碍提醒、热键监听和压测 runner 启动。
  步骤：注入隔离 `UserDefaults`、spy hotkey factory、spy takeover controller 和 spy stress runner，然后执行 `applicationDidFinishLaunching`。
  验证：Home tab 被选中，面板控制器、主/应用内热键监视器、多个 observer、状态栏项都已安装；无障碍提醒被触发一次；takeover 协调和 stress runner 启动成功。

- `testAppDelegateLaunchSkipsAccessibilityPromptWhenAlreadyPromptedOrReminderDisabled`
  场景：用户已看过权限提醒，或主动关闭提醒。
  步骤：分别配置“已提示过”和“提醒已关闭”两种持久化状态，再执行启动。
  验证：两种场景都不会再次发起无障碍权限请求。

- `testAppDelegateTerminationRemovesObserversStopsHotkeyMonitorsAndRestoresTakeover`
  场景：应用退出时需要完整清理资源。
  步骤：先启动应用代理，再执行 `applicationWillTerminate`。
  验证：热键、可见性、语言等 observer 被移除；主热键与 In-App 热键监视器都会停止；系统快捷键 takeover 被恢复。

- `testAppDelegateHotkeyObserverUsesPostedConfigurationsImmediately`
  场景：通过通知广播新的热键配置。
  步骤：启动后向 `flowTabReRegisterHotkeys` 发送新的主热键与 In-App 热键配置。
  验证：旧监视器会停止，新监视器按通知内容立即重建，且 takeover 会按新主热键重新协调。

- `testAppDelegateDirectHotkeyReloadRegistersImmediatelyWithoutNotificationEcho`
  场景：直接调用应用代理方法请求热键重载。
  步骤：启动应用后执行 `requestHotkeyReload(using:source:)`。
  验证：效果与通知式重载一致，但不会依赖额外通知回环。

- `testAppDelegateSkipsInAppHotkeyMonitorWhenShortcutConflictsWithMainHotkey`
  场景：In-App 快捷键与主快捷键冲突。
  步骤：把 In-App 快捷键持久化为与主快捷键相同后启动应用。
  验证：只注册主热键监视器，不创建 In-App 热键监视器。

- `testAppDelegateLaunchWithUITestBootstrapArgumentsSeedsLogsAndOpensSearch`
  场景：应用通过 UI test 启动参数做启动自举。
  步骤：注入重置 defaults、运行时日志级别、预置日志数和“启动即打开搜索”的参数后启动应用代理。
  验证：受影响的偏好会被重置并重写；Home tab 恢复为首页；日志被清理后重新预置；Switchter 面板进入搜索态；stress runner 与热键监视器正常启动。

- `testAppDelegateLaunchOpenSwitcherWithoutResultsDoesNotEnterSearchAndSeedZeroSkipsSeededLogs`
  场景：启动时只要求打开 Switcher，且快照为空、预置日志数为 0。
  步骤：注入 `--flowtab-ui-open-switcher` 与 `--flowtab-ui-seed-logs 0` 启动参数。
  验证：面板不会进入搜索态，也不会写入任何预置日志，但热键监视器仍会正常创建。

### FlowTabPriorityCoverage / SwitcherPanelController 搜索、快捷键与打断恢复行为测试

来源：`FlowTabTests/FlowTabPriorityCoverageTests.swift`

- `testSwitcherPanelControllerSearchTabTogglesScope`
  场景：搜索态下按 Tab 在应用搜索和窗口搜索间切换。
  步骤：启动会话、进入搜索态后发送 `Tab` 键事件。
  验证：事件被消费，搜索范围从 `app` 切换到 `window`。

- `testSwitcherPanelControllerSearchArrowKeysOnlyReturnToInputFromFirstResult`
  场景：搜索输入框与结果列表间的焦点切换。
  步骤：进入搜索态后依次按下箭头、再按上箭头返回顶部。
  验证：第一次向下会把焦点从输入框移到第一个结果；再次向下继续移动结果索引；回到第一个结果后再按上才会把焦点还给输入框。

- `testSwitcherPanelControllerSearchWrapRequestsScrollBackToFirstResult`
  场景：搜索结果选中项从最后一条回环到第一条时，面板层需要重新发出滚动请求。
  步骤：使用 10 条 `Mock Wrap xx` 结果启动搜索态，连续向下移动到最后一项后再按一次下方向键。
  验证：选中索引回到 `0`，并且测试钩子记录到最后一次滚动请求对应第一条结果 ID，说明视图同步信号没有丢失。

- `testSwitcherPanelControllerSearchEnterAppliesSelectionAndEscapeExitsSearch`
  场景：搜索态内按回车应用结果，按 Escape 分层退出。
  步骤：在搜索态选择一个应用结果后按回车；再次进入搜索，先把焦点移到结果列表，再连续按两次 Escape。
  验证：回车会应用结果并退出搜索；第一次 Escape 只把焦点还给输入框；第二次 Escape 才真正退出搜索态。

- `testSwitcherPanelControllerEnterStartsSearchFromMainSwitcher`
  场景：主切换器处于标准态时按回车开启搜索。
  步骤：启动主会话后发送回车键事件。
  验证：事件被消费，搜索态开启且输入框获得焦点，会话本身仍然存在。

- `testSwitcherPanelControllerMarkedTextPassesSearchShortcutKeysThrough`
  场景：输入法组合态下，不应把 Tab/Enter/Escape 当成搜索快捷键处理。
  步骤：进入搜索态并标记 `markedText = true` 后，依次发送 Tab、Enter、Escape。
  验证：三个事件都返回未处理，搜索范围和搜索态保持不变。

- `testSwitcherPanelControllerQuitShortcutTriggersTerminateSelectedAppFlow`
  场景：在切换器里按退出快捷键结束当前应用。
  步骤：注入可终止的应用列表、终止请求与“进程仍在运行”的检测结果后发送退出热键。
  验证：事件被消费，模型会进入“正在终止该应用”的中间状态，但会话仍保持存在。

- `testSwitcherPanelControllerQuitFrontmostAppInAppLayerKeepsSessionAfterAutomaticTerminationRefresh`
  场景：在应用层退出当前选中应用后，通过轮询自动刷新布局。
  步骤：启动主会话，发送退出快捷键，并让进程检查立即返回“已退出”。
  验证：布局会自动刷新到新的应用集合，会话继续存在并自动选中下一个应用。

- `testSwitcherPanelControllerInAppHotkeyReleaseCommitsFocusedWindowSession`
  场景：In-App 窗口热键松开时直接提交当前窗口选择。
  步骤：以当前前台应用启动 focused window session，然后模拟主修饰键松开。
  验证：会话结束，并向激活器发送当前选中窗口的目标。

- `testSwitcherPanelControllerGlobalHotkeyAdvanceAndReleaseCommitSession`
  场景：全局主热键按下期间继续前移，再在松开时提交。
  步骤：启动全局会话，触发一次前进，再模拟主修饰键松开。
  验证：当前选中应用会变化，随后会话被提交并结束。

- `testSwitcherPanelControllerDownArrowInAppCycleEntersWindowLayer`
  场景：主切换器应用层按下方向键进入窗口层。
  步骤：启动全局会话后发送下方向键。
  验证：事件被消费，会话切换为窗口层，并开启预览层模式。

- `testSwitcherPanelControllerFlagsChangedReleaseConfirmationEndsSession`
  场景：通过 `flagsChanged` 事件确认主修饰键已松开。
  步骤：启动全局会话，把“主修饰键仍按下” override 设为 `false`，再发送一次 `flagsChanged`。
  验证：短暂等待后会话被结束。

- `testSwitcherPanelControllerMouseDownOutsideSearchCancelsSession`
  场景：搜索态下点击面板外部。
  步骤：启动全局会话、进入搜索态，并让面板命中测试始终返回 `false`。
  验证：外部点击会直接取消当前会话。

- `testSwitcherPanelControllerActiveSpaceChangeKeepsSessionVisibleWithoutReactivatingApp`
  场景：活跃空间变化时，面板短暂不可见但随后恢复。
  步骤：启动全局会话，模拟应用不处于激活态，先让面板 occlusion 为空，再延迟恢复为可见后主动调用 `handleActiveSpaceDidChangeForTesting()`。
  验证：会话仍保留，不会强行再次激活应用，也不会进入 suppress replay 状态。

- `testSwitcherPanelControllerActiveSpaceNotificationKeepsSessionVisibleWithoutReactivatingApp`
  场景：通过系统通知触发活跃空间变化，且面板能自行恢复可见。
  步骤：与上一用例相同，但改为发布 `NSWorkspace.activeSpaceDidChangeNotification`。
  验证：会话继续存在，不会重复激活应用。

- `testSwitcherPanelControllerActiveSpaceNotificationCancelsSessionAfterModifierRelease`
  场景：活跃空间变化发生时，主修饰键和主键都已松开。
  步骤：启动全局会话后发布活跃空间变化通知。
  验证：会话立即取消，并在短暂抑制重放后恢复正常状态。

- `testSwitcherPanelControllerActiveSpaceChangeCancelsSessionAfterModifierRelease`
  场景：主动处理活跃空间变化时也要遵循同样规则。
  步骤：启动全局会话并直接调用 `handleActiveSpaceDidChangeForTesting()`。
  验证：会话取消，`suppressHotkeyReplayUntilRelease` 先置为 `true` 再自动恢复。

- `testSwitcherPanelControllerRecoverableOcclusionKeepsSessionVisible`
  场景：面板因为暂时性遮挡变为不可见，但很快恢复。
  步骤：启动会话后先让 occlusion 为空，再延迟恢复为 `.visible`，然后触发 occlusion 变化处理。
  验证：会话保持存在，不会误判为系统打断。

- `testSwitcherPanelControllerSystemInterruptionsCancelSessionAndSuppressReplayUntilRelease`
  场景：空间变化、不可恢复遮挡、失去 key window 等系统打断都需要取消会话。
  步骤：依次模拟活跃空间变化、持续 occlusion 为空、面板失去 key window。
  验证：前两种情况会取消会话并暂时抑制热键重放，最后一种情况会直接结束会话。

- `testSwitcherPanelControllerDelayedAutoEnterWindowLayerTriggersAfterConfiguredDelay`
  场景：自动进入窗口层使用显式 override 延迟。
  步骤：启动主会话，设置 `windowLayerPresentationDelayOverride = 0.01`，安排延迟进入窗口层。
  验证：等待后会话从应用层切换到当前应用的窗口层。

- `testSwitcherPanelControllerDelayedAutoEnterWindowLayerUsesPreferenceDelay`
  场景：自动进入窗口层使用用户偏好中的延迟值。
  步骤：临时把偏好延迟设为 `0.01`，启动主会话并安排延迟进入。
  验证：等待后同样会自动进入窗口层。

- `testSwitcherPanelControllerShowSkipsHidingRegularWindowsWhileAppIsActive`
  场景：应用已处于激活态时展示切换器。
  步骤：让 `appIsActiveOverride = true` 后执行 `presentGlobalHotkeySessionForTesting()`。
  验证：不会调用隐藏普通窗口逻辑。

- `testSwitcherPanelControllerShowStillHidesRegularWindowsWhileAppIsInactive`
  场景：应用未激活时展示切换器。
  步骤：让 `appIsActiveOverride = false` 后执行 `presentGlobalHotkeySessionForTesting()`。
  验证：会调用一次隐藏普通窗口逻辑。

- `testSwitcherPanelControllerFewAppsShrinkPanelWidthWithoutChangingSpacing`
  场景：少量应用时，面板宽度应收窄但栅格间距保持稳定。
  步骤：为 5 个应用生成布局数据并调用 `updatePanelSizeForTesting`。
  验证：tile 大小保持 90，spacing 保持 10，总宽度收敛到预期值。

- `testSwitcherPanelControllerManyAppsReduceTileSizeWhileKeepingSpacingConstant`
  场景：大量应用时，需要压缩 tile 尺寸而非压缩间距。
  步骤：为 20 个应用生成布局数据并更新面板尺寸。
  验证：spacing 仍保持 10，tile 大小变小，总宽度扩展到预期最大值。

### FlowTabPriorityCoverage / 运行时快照、窗口预览与缓存行为测试

来源：`FlowTabTests/FlowTabPriorityCoverageTests.swift`

- `testRuntimeAppLayerProjectionFilterCoversCurrentProcessAndMinimizedApps`
  场景：runtime app-layer projection filter 同时处理当前进程和“仅最小化窗口”应用。
  步骤：分别传入不同 activation policy、终止状态、PID 与最小化策略组合。
  验证：只有满足条件的应用会进入应用层；当关闭“隐藏仅最小化应用”时，最小化应用也可保留。

- `testRuntimeActivatorShortCircuitsActivationForCurrentProcessTarget`
  场景：激活目标就是当前进程。
  步骤：注入 `activateCurrentAppIfNeededOverride` 和 `requestActivationOverride` 后激活当前应用。
  验证：只走“当前应用短路激活”路径，不会再调用通用激活请求。

- `testRuntimeActivatorWindowActivationRestoresMinimizedWindowAndFallsBackWhenMissing`
  场景：窗口目标可能是最小化窗口，也可能已经不存在。
  步骤：先激活一个最小化窗口，再激活一个缺失窗口。
  验证：最小化窗口会强制带恢复标记聚焦；缺失窗口则只激活应用，不做窗口聚焦。

- `testRuntimeFullRepairProjectionAssemblerSelectsPrimaryRowsAndFiltersMinimizedOnlyApps`
  场景：同一 bundle 存在多个 PID、部分应用只有最小化窗口。
  步骤：构造多 PID 的 Mail/Chat/Notes 数据，开启“隐藏仅最小化应用”，并执行组装。
  验证：每个 bundle 只选主行，最小化-only 的应用被过滤，输出顺序按 rank 与时间排序。

- `testRuntimeFullRepairProjectionAssemblerIncludesMinimizedAppsWhenFilterDisabledAndUsesFallbackGroup`
  场景：关闭最小化过滤，且应用没有 bundle ID。
  步骤：构造两个只有最小化窗口、无 bundle ID 的应用并执行组装。
  验证：两者都会保留，且分组 ID 会按回退名称首字母生成。

- `testRuntimeWindowPreviewProviderGuessesDarkLightAndUnknownTitleBars`
  场景：预览图标题栏样式推断。
  步骤：分别传入纯黑、纯白和条纹噪声预览图。
  验证：黑图推断为 `dark`，白图推断为 `light`，噪声图返回 `nil`。

- `testRuntimeWindowPreviewProviderCandidateWindowOrderingForPreferredAndTitleMatches`
  场景：窗口预览匹配时需要优先尝试首选窗口 ID 和标题相似窗口。
  步骤：构造多个 live window 候选并查询候选 ID 顺序。
  验证：首选窗口 ID 排在第一，其余窗口按标题匹配优先级依次排列。

- `testRuntimeWindowPreviewProviderOwnerPIDPathKeepsPreferredWindowFirst`
  场景：仅依赖 owner PID 时，仍要优先尝试首选窗口。
  步骤：传入 preferred window ID、owner PID 和不存在的标题。
  验证：返回的候选 ID 列表仍以 preferred window ID 开头。

- `testRuntimeWindowPreviewProviderScaledPreviewSizeAndImageDownscaleBehavior`
  场景：大尺寸预览图需要缩放，小尺寸图保持原样。
  步骤：分别测试超大、正常和极小尺寸，并对真实图像执行缩放。
  验证：超大图按比例压缩到上限，正常尺寸不变，极小尺寸至少保留 `1x1`。

- `testRuntimeAppIdentityGroupIDMappingCoversFallbackAndBundleShapes`
  场景：分组 ID 推导需要覆盖无 bundle ID、标准三段 bundle ID、单段 bundle ID 和空字符串。
  步骤：调用 `RuntimeAppIdentity.groupID` 测试四种输入。
  验证：分组 ID 分别回退为首字母、组织段、原 bundle ID 或通用 `apps`。

- `testRuntimeSnapshotProviderResolveCGWindowIDCoversExactInsensitiveFallbackAndExhaustedCases`
  场景：CGWindowID 解析需要支持精确匹配、大小写不敏感匹配、按索引回退和用尽后的空结果。
  步骤：构造多条 CG 窗口记录并多次调用 `resolveCGWindowIDForTesting`。
  验证：每次都会优先取未使用且最匹配的窗口；全部用尽时返回 `nil`。

- `testAXWindowInspectorHelpersRoundTripWindowIDsAndHandleSystemElementLookups`
  场景：AX 窗口辅助工具要正确编码/解码窗口 ID，并兼容系统级元素查询。
  步骤：生成一个 `ax:<pid>:<index>` ID，再对系统级 AX 元素读取 role、switchable、minimized 和 title。
  验证：编码解码互相可逆；无效字符串返回 `nil`；系统元素查询不会崩溃，辅助判断逻辑成立。

- `testBoundedImageCacheStoresAndClearsImages`
  场景：有界图片缓存的基础读写。
  步骤：插入一张图片后立即读取，再执行 `removeAll()`。
  验证：插入后能读到，清空后读不到。

- `testBoundedImageCacheHandlesImagesWithoutBitmapRepresentations`
  场景：缓存需要兼容只有矢量尺寸、没有位图表示的 `NSImage`。
  步骤：插入一张 vector-only 图片。
  验证：缓存仍能存取该图片，不因缺少位图表示失败。

- `testAppIconProviderCachesResolvedIconsAndMemoizesMissingApps`
  场景：应用图标提供器既要缓存命中的图标，也要记住缺失项避免重复查找。
  步骤：先请求一个存在的应用两次，再请求一个不存在的应用两次。
  验证：存在应用只会查一次 URL 和图标文件路径；缺失应用也只会触发一次查找。
