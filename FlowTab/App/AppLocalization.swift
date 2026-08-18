import Foundation
import FlowTabCore

extension ThemeMode {
    var displayName: String {
        switch self {
        case .followSystem:
            return AppStrings.text(.themeFollowSystem)
        case .light:
            return AppStrings.text(.themeLight)
        case .dark:
            return AppStrings.text(.themeDark)
        }
    }
}

enum AppStringKey: String {
    case themeFollowSystem
    case themeLight
    case themeDark
    case menuSettings
    case menuLogs
    case menuOpenLogs
    case menuOpenSettings
    case menuOpenHome
    case menuQuit
    case menuQuitFlowTab
    case tabHome
    case tabLogs
    case tabSettings
    case sidebarWorkbench
    case permissionGuideAll
    case permissionGuideAccessibility
    case permissionGuideScreenCapture
    case permissionGuideReady
    case actionGoToSettings
    case actionDontRemindAgain
    case homePageSubtitle
    case homeAppLayerTitle
    case homeAppLayerSubtitle
    case homeAppCount
    case homeNoSwitchableApps
    case homeTriggerHotkeyFirst
    case homeWindowLayerTitle
    case homeCurrentAppWindows
    case homeAppWindowsOf
    case homeWindowCount
    case homeWindowDataLoading
    case homeReadingWindowsOf
    case homeNoSwitchableWindows
    case homeConfirmAccessibility
    case homeNoWindowData
    case homeWaitCacheUpdate
    case homeAppNotShownBadge
    case homeStatsTotalApps
    case homeStatsVisibleApps
    case homeStatsHiddenApps
    case homeStatsTotalWindows
    case homeWindowStatusCurrent
    case homeWindowStatusMinimized
    case homeWindowStatusSwitchable
    case homePermissionAccessibility
    case homePermissionScreenCapture
    case homePermissionGranted
    case homePermissionMissing
    case hotkeyCommandTabTakeoverActive
    case hotkeyCommandTabTakeoverInactive
    case hotkeyConflict
    case hotkeyModifierPermissionlessRequirement
    case hotkeyMainKeyPermissionlessRequirement
    case hotkeyMainSummary
    case hotkeyInAppSummary
    case hotkeySummaryReverseLabel
    case hotkeySummaryQuitLabel
    case hotkeySummaryInAppLabel
    case hotkeyRowMainModifiers
    case hotkeyRowMainReverseModifiers
    case hotkeyRowMainKey
    case hotkeyRowQuitKey
    case hotkeyRowInAppShortcut
    case hotkeyRowInAppReverseModifiers
    case hotkeyRecorderPrompt
    case hotkeyRecorderModifierRequired
    case settingsPageTitle
    case settingsPageSubtitle
    case settingsCardAppearanceTitle
    case settingsCardAppearanceSubtitle
    case settingsCardWindowBehaviorTitle
    case settingsCardWindowBehaviorSubtitle
    case settingsCardPermissionTitle
    case settingsCardPermissionSubtitle
    case settingsCardSearchTitle
    case settingsCardSearchSubtitle
    case settingsCardAppVisibilityTitle
    case settingsCardAppVisibilitySubtitle
    case settingsCardHotkeyTitle
    case settingsCardHotkeySubtitle
    case appearanceDescription
    case appearanceShowShortcutHint
    case appearanceShowAppWindow
    case appearanceThemeMode
    case appearanceLanguage
    case languageSimplifiedChinese
    case languageEnglish
    case windowBehaviorNote
    case windowBehaviorSecondUnit
    case windowBehaviorAutoEnterDelay
    case windowBehaviorAutoRestoreMinimized
    case windowBehaviorHideMinimizedApps
    case searchSummaryEnabled
    case searchSummaryDisabled
    case searchSummaryAccessibilityRequired
    case searchEnable
    case searchDefaultScope
    case searchScopeApp
    case searchScopeWindow
    case appVisibilitySummary
    case appVisibilityManage
    case appVisibilityManagerTitle
    case appVisibilityManagerSubtitle
    case appVisibilityBack
    case appVisibilitySearchPlaceholder
    case appVisibilityFilterAll
    case appVisibilityFilterHidden
    case appVisibilityFilterRunning
    case appVisibilityNoApps
    case appVisibilityNoSelectionTitle
    case appVisibilityNoSelectionSubtitle
    case appVisibilityShowInSwitcher
    case appVisibilityBundleID
    case appVisibilityPath
    case appVisibilityStatus
    case appVisibilityStatusVisible
    case appVisibilityStatusHidden
    case appVisibilityEffectNote
    case appVisibilityHiddenBadge
    case permissionAccessibilityGranted
    case permissionAccessibilityDenied
    case permissionAccessibilityManage
    case permissionAccessibilityRequest
    case permissionAccessibilityManageActionLabel
    case permissionAccessibilityRequestActionLabel
    case permissionScreenGranted
    case permissionScreenDenied
    case permissionScreenManage
    case permissionScreenRequest
    case permissionScreenManageActionLabel
    case permissionScreenRequestActionLabel
    case permissionAccessibilityDetail
    case permissionScreenDetail
    case permissionHomeReminderToggle
    case permissionLaunchAtLoginToggle
    case logsPageTitle
    case logsPageSubtitle
    case logsSectionTitle
    case logsSectionSubtitle
    case logsPrivacyNotice
    case logsLevel
    case logsDirectory
    case logsOpenDirectory
    case logsClear
    case logsEmptyHint
    case alertScreenDeniedTitle
    case alertScreenDeniedMessage
    case alertOpenSystemSettings
    case alertLater
    case contentViewHint
    case panelHintEnterToSearch
    case panelHintSearchMode
    case panelInputPlaceholder
    case panelSearchLabel
    case panelNoResult
}

enum AppStrings {
    private static let fallbackLanguage: AppLanguage = .simplifiedChinese

    private static let translations: [AppLanguage: [AppStringKey: String]] = [
        .simplifiedChinese: [
            .themeFollowSystem: "跟随系统",
            .themeLight: "浅色",
            .themeDark: "深色",
            .menuSettings: "设置",
            .menuLogs: "日志",
            .menuOpenLogs: "打开日志",
            .menuOpenSettings: "打开设置",
            .menuOpenHome: "打开应用首页",
            .menuQuit: "退出",
            .menuQuitFlowTab: "退出 FlowTab",
            .tabHome: "首页",
            .tabLogs: "日志",
            .tabSettings: "设置",
            .sidebarWorkbench: "工作台",
            .permissionGuideAll: "请开启辅助功能和屏幕录制权限，部分功能才能正常使用。",
            .permissionGuideAccessibility: "请开启辅助功能权限，应用切换与窗口功能才能正常使用。",
            .permissionGuideScreenCapture: "请开启屏幕录制权限，窗口预览功能才能正常使用。",
            .permissionGuideReady: "权限已开启。",
            .actionGoToSettings: "前往设置",
            .actionDontRemindAgain: "不再提示",
            .homePageSubtitle: "概览应用与窗口使用情况",
            .homeAppLayerTitle: "应用层",
            .homeAppLayerSubtitle: "当前可切换应用",
            .homeAppCount: "{count} 个应用",
            .homeNoSwitchableApps: "无可切换应用",
            .homeTriggerHotkeyFirst: "先触发一次 {hotkey}",
            .homeWindowLayerTitle: "窗口层",
            .homeCurrentAppWindows: "当前应用窗口",
            .homeAppWindowsOf: "{app} 的窗口",
            .homeWindowCount: "{count} 个窗口",
            .homeWindowDataLoading: "窗口数据加载中",
            .homeReadingWindowsOf: "正在读取 {app} 的窗口",
            .homeNoSwitchableWindows: "当前应用无可切换窗口",
            .homeConfirmAccessibility: "请确认辅助功能权限已授权",
            .homeNoWindowData: "暂无窗口数据",
            .homeWaitCacheUpdate: "等待缓存更新",
            .homeAppNotShownBadge: "不展示",
            .homeStatsTotalApps: "应用总数",
            .homeStatsVisibleApps: "可见应用",
            .homeStatsHiddenApps: "隐藏应用",
            .homeStatsTotalWindows: "窗口总数",
            .homeWindowStatusCurrent: "当前",
            .homeWindowStatusMinimized: "最小化",
            .homeWindowStatusSwitchable: "可切换",
            .homePermissionAccessibility: "辅助权限",
            .homePermissionScreenCapture: "屏幕录制",
            .homePermissionGranted: "已授予",
            .homePermissionMissing: "未授权",
            .hotkeyCommandTabTakeoverActive: "已接管系统 Command + Tab / Command + Shift + Tab，退出 FlowTab 后会自动恢复。",
            .hotkeyCommandTabTakeoverInactive: "检测到 Command + Tab 组合：FlowTab 会自动尝试接管系统 Command + Tab / Command + Shift + Tab。",
            .hotkeyConflict: "已被使用",
            .hotkeyModifierPermissionlessRequirement: "未授权时仅支持修饰键",
            .hotkeyMainKeyPermissionlessRequirement: "未授权时仅支持任意修饰键加一个普通键或功能键",
            .hotkeyMainSummary: "当前：{main}（{reverseLabel}：{reverse}），{quitLabel}：{quit}",
            .hotkeyInAppSummary: "{inAppLabel}：{main}（{reverseLabel}：{reverse}）",
            .hotkeySummaryReverseLabel: "反向",
            .hotkeySummaryQuitLabel: "结束应用",
            .hotkeySummaryInAppLabel: "应用内窗口",
            .hotkeyRowMainModifiers: "主修饰键",
            .hotkeyRowMainReverseModifiers: "反向修饰键",
            .hotkeyRowMainKey: "主切换按键",
            .hotkeyRowQuitKey: "结束应用按键",
            .hotkeyRowInAppShortcut: "应用内窗口",
            .hotkeyRowInAppReverseModifiers: "应用内反向修饰键",
            .hotkeyRecorderPrompt: "请按下快捷键",
            .hotkeyRecorderModifierRequired: "请至少按下一个按键",
            .settingsPageTitle: "设置",
            .settingsPageSubtitle: "基础显示设置、快捷键与权限",
            .settingsCardAppearanceTitle: "外观",
            .settingsCardAppearanceSubtitle: "显示与主题",
            .settingsCardWindowBehaviorTitle: "窗口行为",
            .settingsCardWindowBehaviorSubtitle: "窗口层进入与最小化处理",
            .settingsCardPermissionTitle: "权限",
            .settingsCardPermissionSubtitle: "辅助功能与屏幕录制",
            .settingsCardSearchTitle: "搜索",
            .settingsCardSearchSubtitle: "搜索开关、范围与交互说明",
            .settingsCardAppVisibilityTitle: "应用可见性",
            .settingsCardAppVisibilitySubtitle: "管理不出现在切换器中的应用",
            .settingsCardHotkeyTitle: "快捷键",
            .settingsCardHotkeySubtitle: "主切换与结束应用按键",
            .appearanceDescription: "关闭后，当前应用将仅作为菜单栏辅助应用运行。",
            .appearanceShowShortcutHint: "显示快捷键提示",
            .appearanceShowAppWindow: "像普通应用一样显示",
            .appearanceThemeMode: "主题模式",
            .appearanceLanguage: "语言",
            .languageSimplifiedChinese: "简体中文",
            .languageEnglish: "English",
            .windowBehaviorNote: "说明：该过滤依赖辅助功能权限。未授权时无法判断最小化状态，不会过滤应用层。",
            .windowBehaviorSecondUnit: "秒",
            .windowBehaviorAutoEnterDelay: "窗口层自动进入延迟",
            .windowBehaviorAutoRestoreMinimized: "切换到最小化窗口时自动恢复打开",
            .windowBehaviorHideMinimizedApps: "应用层隐藏仅最小化应用",
            .searchSummaryEnabled: "面板默认从应用层开始；按 Enter 或 ↑ 进入搜索。",
            .searchSummaryDisabled: "已关闭搜索：面板仅显示应用层与窗口层。",
            .searchSummaryAccessibilityRequired: "窗口搜索需要辅助功能权限；授权后可选择窗口范围。",
            .searchEnable: "启用搜索功能",
            .searchDefaultScope: "默认搜索范围",
            .searchScopeApp: "应用",
            .searchScopeWindow: "窗口",
            .appVisibilitySummary: "隐藏后不会出现在 Option + Tab 应用层和搜索结果中。",
            .appVisibilityManage: "管理",
            .appVisibilityManagerTitle: "应用可见性",
            .appVisibilityManagerSubtitle: "已隐藏 {count} 个应用",
            .appVisibilityBack: "返回设置",
            .appVisibilitySearchPlaceholder: "搜索应用、Bundle ID 或路径",
            .appVisibilityFilterAll: "全部",
            .appVisibilityFilterHidden: "已隐藏",
            .appVisibilityFilterRunning: "运行中",
            .appVisibilityNoApps: "没有匹配应用",
            .appVisibilityNoSelectionTitle: "选择一个应用",
            .appVisibilityNoSelectionSubtitle: "在左侧列表中选择应用后调整可见性。",
            .appVisibilityShowInSwitcher: "在 FlowTab 切换器中显示",
            .appVisibilityBundleID: "Bundle ID",
            .appVisibilityPath: "路径",
            .appVisibilityStatus: "状态",
            .appVisibilityStatusVisible: "显示",
            .appVisibilityStatusHidden: "已隐藏",
            .appVisibilityEffectNote: "该设置影响全局 Option + Tab 应用面板、应用搜索以及对应窗口搜索结果。当前应用内的窗口切换不受影响。",
            .appVisibilityHiddenBadge: "已隐藏",
            .permissionAccessibilityGranted: "辅助功能权限：已授权",
            .permissionAccessibilityDenied: "辅助功能权限：未授权",
            .permissionAccessibilityManage: "管理辅助功能权限",
            .permissionAccessibilityRequest: "请求辅助功能权限",
            .permissionAccessibilityManageActionLabel: "管理辅助功能权限",
            .permissionAccessibilityRequestActionLabel: "请求辅助功能权限",
            .permissionScreenGranted: "屏幕录制权限：已授权",
            .permissionScreenDenied: "屏幕录制权限：未授权",
            .permissionScreenManage: "管理屏幕录制权限",
            .permissionScreenRequest: "请求屏幕录制权限",
            .permissionScreenManageActionLabel: "管理屏幕录制权限",
            .permissionScreenRequestActionLabel: "请求屏幕录制权限",
            .permissionAccessibilityDetail: "用于应用切换、应用内窗口切换、多普通键快捷键监听和最小化窗口处理。",
            .permissionScreenDetail: "用于显示窗口真实预览画面；未授权时仅显示兜底信息。",
            .permissionHomeReminderToggle: "无权限时是否在首页提示获取权限",
            .permissionLaunchAtLoginToggle: "允许开机启动 FlowTab",
            .logsPageTitle: "日志",
            .logsPageSubtitle: "脱敏运行日志与清理",
            .logsSectionTitle: "日志",
            .logsSectionSubtitle: "所有持久化内容均为脱敏元数据",
            .logsPrivacyNotice: "日志等级决定写入的最低事件等级，DEBUG 和 INFO 会增加高频脱敏事件。日志仅保存事件类型、长度、计数和安装内稳定指纹；窗口标题、搜索词、浏览器标签标题和应用路径统一转换为脱敏元数据。",
            .logsLevel: "日志等级",
            .logsDirectory: "本地日志目录：{path}",
            .logsOpenDirectory: "打开目录",
            .logsClear: "清空日志",
            .logsEmptyHint: "暂无日志。触发 {hotkey} 后再回来看。",
            .alertScreenDeniedTitle: "屏幕录制权限已被拒绝",
            .alertScreenDeniedMessage: "macOS 不会再次弹出授权窗口。请前往系统设置的“隐私与安全性-屏幕录制”中手动开启权限。",
            .alertOpenSystemSettings: "打开系统设置",
            .alertLater: "稍后",
            .contentViewHint: "应用在后台运行，按 {mainHotkey} 呼出切换面板，按住 {quitHotkey} 结束当前所选应用",
            .panelHintEnterToSearch: "Enter / ↑ 进入搜索",
            .panelHintSearchMode: "Tab 切换范围 · ←/→ 移动光标 · ↓ 进入结果 · Enter 激活 · Esc 清空/关闭",
            .panelInputPlaceholder: "输入关键词搜索",
            .panelSearchLabel: "搜索",
            .panelNoResult: "没有匹配结果"
        ],
        .english: [
            .themeFollowSystem: "System",
            .themeLight: "Light",
            .themeDark: "Dark",
            .menuSettings: "Settings",
            .menuLogs: "Logs",
            .menuOpenLogs: "Open Logs",
            .menuOpenSettings: "Open Settings",
            .menuOpenHome: "Open Home",
            .menuQuit: "Quit",
            .menuQuitFlowTab: "Quit FlowTab",
            .tabHome: "Home",
            .tabLogs: "Logs",
            .tabSettings: "Settings",
            .sidebarWorkbench: "Workspace",
            .permissionGuideAll: "Please enable both Accessibility and Screen Recording permissions for full functionality.",
            .permissionGuideAccessibility: "Please enable Accessibility permission for app switching and window features.",
            .permissionGuideScreenCapture: "Please enable Screen Recording permission for window previews.",
            .permissionGuideReady: "Permissions granted.",
            .actionGoToSettings: "Go to Settings",
            .actionDontRemindAgain: "Don't remind again",
            .homePageSubtitle: "Overview of app and window usage",
            .homeAppLayerTitle: "App Layer",
            .homeAppLayerSubtitle: "Switchable apps",
            .homeAppCount: "{count} apps",
            .homeNoSwitchableApps: "No switchable apps",
            .homeTriggerHotkeyFirst: "Trigger {hotkey} once first",
            .homeWindowLayerTitle: "Window Layer",
            .homeCurrentAppWindows: "Current app windows",
            .homeAppWindowsOf: "{app} windows",
            .homeWindowCount: "{count} windows",
            .homeWindowDataLoading: "Loading window data",
            .homeReadingWindowsOf: "Reading {app} windows",
            .homeNoSwitchableWindows: "No switchable windows in current app",
            .homeConfirmAccessibility: "Please confirm Accessibility permission is granted",
            .homeNoWindowData: "No window data",
            .homeWaitCacheUpdate: "Waiting for cache update",
            .homeAppNotShownBadge: "Not shown",
            .homeStatsTotalApps: "Total Apps",
            .homeStatsVisibleApps: "Visible Apps",
            .homeStatsHiddenApps: "Hidden Apps",
            .homeStatsTotalWindows: "Total Windows",
            .homeWindowStatusCurrent: "Current",
            .homeWindowStatusMinimized: "Minimized",
            .homeWindowStatusSwitchable: "Switchable",
            .homePermissionAccessibility: "Accessibility",
            .homePermissionScreenCapture: "Screen Recording",
            .homePermissionGranted: "Granted",
            .homePermissionMissing: "Missing",
            .hotkeyCommandTabTakeoverActive: "System Command + Tab / Command + Shift + Tab is now taken over and will be restored after FlowTab exits.",
            .hotkeyCommandTabTakeoverInactive: "Command + Tab combination detected: FlowTab will try to take over system Command + Tab / Command + Shift + Tab.",
            .hotkeyConflict: "Already in use",
            .hotkeyModifierPermissionlessRequirement: "Only modifier keys are supported without Accessibility permission",
            .hotkeyMainKeyPermissionlessRequirement: "Use any modifiers with exactly one ordinary or function key without Accessibility permission",
            .hotkeyMainSummary: "Current: {main} ({reverseLabel}: {reverse}), {quitLabel}: {quit}",
            .hotkeyInAppSummary: "{inAppLabel}: {main} ({reverseLabel}: {reverse})",
            .hotkeySummaryReverseLabel: "Reverse",
            .hotkeySummaryQuitLabel: "Quit app",
            .hotkeySummaryInAppLabel: "In-app windows",
            .hotkeyRowMainModifiers: "Main modifiers",
            .hotkeyRowMainReverseModifiers: "Reverse modifiers",
            .hotkeyRowMainKey: "Main switch key",
            .hotkeyRowQuitKey: "Quit app key",
            .hotkeyRowInAppShortcut: "In-app windows",
            .hotkeyRowInAppReverseModifiers: "In-app reverse modifiers",
            .hotkeyRecorderPrompt: "Press shortcut",
            .hotkeyRecorderModifierRequired: "Press at least one key",
            .settingsPageTitle: "Settings",
            .settingsPageSubtitle: "Display, hotkeys, and permissions",
            .settingsCardAppearanceTitle: "Appearance",
            .settingsCardAppearanceSubtitle: "Display and theme",
            .settingsCardWindowBehaviorTitle: "Window Behavior",
            .settingsCardWindowBehaviorSubtitle: "Window layer entry and minimized handling",
            .settingsCardPermissionTitle: "Permissions",
            .settingsCardPermissionSubtitle: "Accessibility and Screen Recording",
            .settingsCardSearchTitle: "Search",
            .settingsCardSearchSubtitle: "Search switch, scope, and interaction",
            .settingsCardAppVisibilityTitle: "App Visibility",
            .settingsCardAppVisibilitySubtitle: "Manage apps hidden from the switcher",
            .settingsCardHotkeyTitle: "Hotkeys",
            .settingsCardHotkeySubtitle: "Main switch and quit app keys",
            .appearanceDescription: "When turned off, this app runs only as a menu bar helper.",
            .appearanceShowShortcutHint: "Show shortcut hint",
            .appearanceShowAppWindow: "Show like a regular app",
            .appearanceThemeMode: "Theme mode",
            .appearanceLanguage: "Language",
            .languageSimplifiedChinese: "Simplified Chinese",
            .languageEnglish: "English",
            .windowBehaviorNote: "Note: This filter depends on Accessibility permission. Without it, minimized state cannot be detected, so app-layer filtering is skipped.",
            .windowBehaviorSecondUnit: "sec",
            .windowBehaviorAutoEnterDelay: "Window layer auto-enter delay",
            .windowBehaviorAutoRestoreMinimized: "Auto-restore minimized windows when switching",
            .windowBehaviorHideMinimizedApps: "Hide minimized-only apps in app layer",
            .searchSummaryEnabled: "Panel starts from app layer by default; press Enter or ↑ to start search.",
            .searchSummaryDisabled: "Search is disabled: panel only shows app and window layers.",
            .searchSummaryAccessibilityRequired: "Window search requires Accessibility permission. Enable it to choose Window.",
            .searchEnable: "Enable search",
            .searchDefaultScope: "Default search scope",
            .searchScopeApp: "App",
            .searchScopeWindow: "Window",
            .appVisibilitySummary: "Hidden apps do not appear in the Option + Tab app layer or search results.",
            .appVisibilityManage: "Manage",
            .appVisibilityManagerTitle: "App Visibility",
            .appVisibilityManagerSubtitle: "{count} apps hidden",
            .appVisibilityBack: "Back to Settings",
            .appVisibilitySearchPlaceholder: "Search apps, bundle IDs, or paths",
            .appVisibilityFilterAll: "All",
            .appVisibilityFilterHidden: "Hidden",
            .appVisibilityFilterRunning: "Running",
            .appVisibilityNoApps: "No matching apps",
            .appVisibilityNoSelectionTitle: "Select an app",
            .appVisibilityNoSelectionSubtitle: "Choose an app from the list to adjust visibility.",
            .appVisibilityShowInSwitcher: "Show in FlowTab switcher",
            .appVisibilityBundleID: "Bundle ID",
            .appVisibilityPath: "Path",
            .appVisibilityStatus: "Status",
            .appVisibilityStatusVisible: "Visible",
            .appVisibilityStatusHidden: "Hidden",
            .appVisibilityEffectNote: "This affects the global Option + Tab app layer, app search, and matching window search results. In-app window switching is not affected.",
            .appVisibilityHiddenBadge: "Hidden",
            .permissionAccessibilityGranted: "Accessibility: Granted",
            .permissionAccessibilityDenied: "Accessibility: Not granted",
            .permissionAccessibilityManage: "Manage",
            .permissionAccessibilityRequest: "Request",
            .permissionAccessibilityManageActionLabel: "Manage Accessibility permission",
            .permissionAccessibilityRequestActionLabel: "Request Accessibility permission",
            .permissionScreenGranted: "Screen Recording: Granted",
            .permissionScreenDenied: "Screen Recording: Not granted",
            .permissionScreenManage: "Manage",
            .permissionScreenRequest: "Request",
            .permissionScreenManageActionLabel: "Manage Screen Recording permission",
            .permissionScreenRequestActionLabel: "Request Screen Recording permission",
            .permissionAccessibilityDetail: "Used for app switching, in-app window switching, multi-key shortcut monitoring, and minimized-window handling.",
            .permissionScreenDetail: "Used for real window previews; fallback info is shown when not granted.",
            .permissionHomeReminderToggle: "Show Home reminder when permissions are missing",
            .permissionLaunchAtLoginToggle: "Allow FlowTab to launch at login",
            .logsPageTitle: "Logs",
            .logsPageSubtitle: "Redacted runtime logs and cleanup",
            .logsSectionTitle: "Logs",
            .logsSectionSubtitle: "All persisted content is redacted metadata",
            .logsPrivacyNotice: "The selected level controls the minimum event severity written; DEBUG and INFO add high-frequency redacted events. Logs retain only event types, lengths, counts, and installation-stable fingerprints. Window titles, search terms, browser tab titles, and application paths are converted to redacted metadata.",
            .logsLevel: "Log level",
            .logsDirectory: "Local logs directory: {path}",
            .logsOpenDirectory: "Open Directory",
            .logsClear: "Clear Logs",
            .logsEmptyHint: "No logs yet. Trigger {hotkey} and check again.",
            .alertScreenDeniedTitle: "Screen Recording permission was denied",
            .alertScreenDeniedMessage: "macOS will not show the authorization prompt again. Please manually enable it in System Settings > Privacy & Security > Screen Recording.",
            .alertOpenSystemSettings: "Open System Settings",
            .alertLater: "Later",
            .contentViewHint: "The app runs in the background. Press {mainHotkey} to open the switcher panel, then hold {quitHotkey} to quit the selected app.",
            .panelHintEnterToSearch: "Enter / ↑ to search",
            .panelHintSearchMode: "Tab switch scope · ←/→ move cursor · ↓ to results · Enter activate · Esc clear/close",
            .panelInputPlaceholder: "Type to search",
            .panelSearchLabel: "Search",
            .panelNoResult: "No matches"
        ]
    ]

    static func text(
        _ key: AppStringKey,
        replacements: [String: String] = [:],
        language: AppLanguage = AppLanguagePreferencesStore.load()
    ) -> String {
        let languageTable = translations[language] ?? translations[fallbackLanguage] ?? [:]
        let fallbackTable = translations[fallbackLanguage] ?? [:]
        var resolved = languageTable[key] ?? fallbackTable[key] ?? key.rawValue
        for (token, value) in replacements {
            resolved = resolved.replacingOccurrences(of: "{\(token)}", with: value)
        }
        return resolved
    }

    static func appCount(_ count: Int, language: AppLanguage = AppLanguagePreferencesStore.load()) -> String {
        switch language {
        case .simplifiedChinese:
            return text(.homeAppCount, replacements: ["count": "\(count)"], language: language)
        case .english:
            return "\(count) \(englishNoun(singular: "app", plural: "apps", count: count))"
        }
    }

    static func windowCount(_ count: Int, language: AppLanguage = AppLanguagePreferencesStore.load()) -> String {
        switch language {
        case .simplifiedChinese:
            return text(.homeWindowCount, replacements: ["count": "\(count)"], language: language)
        case .english:
            return "\(count) \(englishNoun(singular: "window", plural: "windows", count: count))"
        }
    }

    static func hiddenAppCount(_ count: Int, language: AppLanguage = AppLanguagePreferencesStore.load()) -> String {
        switch language {
        case .simplifiedChinese:
            return text(.appVisibilityManagerSubtitle, replacements: ["count": "\(count)"], language: language)
        case .english:
            return "\(count) \(englishNoun(singular: "app", plural: "apps", count: count)) hidden"
        }
    }

    private static func englishNoun(singular: String, plural: String, count: Int) -> String {
        count == 1 ? singular : plural
    }
}
