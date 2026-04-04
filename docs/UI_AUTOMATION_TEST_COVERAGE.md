# UI 自动化测试覆盖清单（FlowTab）

更新时间：2026-04-04

## 目标与范围

- 目标：将 FlowTab 的可自动化 UI 主路径保持在可回归状态。
- 范围：`FlowTabUITests` / `FlowTabUITestsLaunchTests`，聚焦应用内可稳定自动化的交互。

## 覆盖总览（当前）

- 用例总数：27
- 覆盖域：启动导航、Home、Logs、Settings、Switcher/Search、压测。
- 当前状态：应用内可稳定自动化的核心场景已全部覆盖，无未完成项。
- 边界说明：系统级交互（系统设置页实际跳转、Finder 实际打开目录）仅覆盖入口按钮存在性，不作为稳定 UI 自动化断言目标。

## 覆盖清单（当前）

### 启动与导航

- `testLaunch`（截图冒烟）
- `testLaunchPerformance`（启动性能）
- `testSidebarTabsSwitchContent`（Home/Logs/Settings 切换）

### Home 与权限提示

- `testHomePermissionBannerHiddenWhenPermissionsGranted`（权限已授权时隐藏权限提示横幅）
- `testPermissionReminderTogglePersistsAcrossRelaunch`（权限提醒开关在重启后保持）
- `testPermissionDismissPersistsAcrossRelaunch`（权限提示关闭状态在重启后保持）
- `testHomePageSelectingMockAppUpdatesWindowList`（选择模拟应用后窗口列表同步更新）

### Logs

- `testLogsPageShowsSeededLogsAndClearRemovesOutput`（展示预置日志并验证清空输出）
- `testLogsPageRespectsRuntimeLogLevelVisibility`（运行时日志级别过滤生效）
- `testLogsOpenDirectoryButtonIsVisible`（打开日志目录按钮可见）

### Settings - Appearance

- `testSettingsAppearanceTogglesCanBeChanged`（外观相关开关可切换）
- `testSettingsAppearanceThemeAndLanguagePersistAcrossRelaunch`（主题与语言配置在重启后保持）

### Settings - Window Behavior

- `testSettingsWindowBehaviorDelayAndTogglesPersistAcrossRelaunch`（窗口行为延迟与开关配置在重启后保持）

### Settings - Search

- `testSettingsSearchDisabledPreventsAutoSearchLaunchEntry`（禁用搜索后不自动注入启动入口）
- `testSettingsSearchDefaultWindowScopePersistsAndShowsWindowResults`（默认窗口范围在重启后保持并展示窗口结果）
- `testSettingsSearchDefaultScopeCanSwitchBetweenAppAndWindow`（默认范围可在应用与窗口之间切换）

### Settings - Permission & Hotkey

- `testSettingsPermissionActionButtonsAreVisible`（权限操作按钮可见）
- `testSettingsHotkeySelectionsPersistAcrossRelaunch`（快捷键选择在重启后保持）
- `testSettingsHotkeyInAppControlsDisabledWithoutAccessibilityPermission`（无障碍未授权时 In-App 控件禁用）

### Switcher / Search 面板

- `testSwitcherPanelShowsMockAppTilesInStandardMode`（标准模式展示模拟应用卡片）
- `testSearchPanelEntryAndResultActivation`（搜索输入与结果激活流程可用）
- `testSearchPanelChineseQueryShowsChineseMockResult`（中文查询可命中中文模拟结果）
- `testSearchPanelPinyinInitialsShowChineseMockResult`（拼音首字母查询可命中中文模拟结果）
- `testSearchPanelSharedCsQueryShowsCSGOAndChineseMockResults`（共享关键词查询可同时命中 CSGO 与中文结果）
- `testSearchPanelSegmentedChineseQueryShowsCompoundMockResult`（分词中文查询可命中组合模拟结果）
- `testSwitcherPanelMoveAppThenAutoEnterWindowLayerShowsMockWindows`（移动应用后自动进入窗口层并展示模拟窗口）

### 压测

- `testTabSwitchStressCPUAndMemory`（Tab 切换场景下 CPU 与内存压力验证）

## 回归命令（示例）

```bash
xcodebuild -project FlowTab.xcodeproj -scheme FlowTab \
  -destination 'platform=macOS' \
  -derivedDataPath ./.build-local/test-all \
  test -only-testing:FlowTabUITests
```
