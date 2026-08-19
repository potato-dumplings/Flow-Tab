import AppKit
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testAppLayerHidesZeroWindowNestedAppsWhenOuterHostIsRunning() {
        let hostApp = FakeRunningApplication(
            pid: 10,
            bundleIdentifier: "com.tencent.xinWeChat",
            localizedName: "WeChat",
            bundlePath: "/Applications/WeChat.app"
        )
        let nestedAppEx = FakeRunningApplication(
            pid: 11,
            bundleIdentifier: "com.tencent.flue.WeChatAppEx",
            localizedName: "WeChat",
            bundlePath: "/Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app"
        )
        let nestedMiniProgram = FakeRunningApplication(
            pid: 12,
            bundleIdentifier: "com.tencent.flue.WeApp",
            localizedName: "Mini Program",
            bundlePath: "/Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app/Contents/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeApp.app"
        )
        let ordinaryZeroWindowApp = FakeRunningApplication(
            pid: 20,
            bundleIdentifier: "com.microsoft.VSCode",
            localizedName: "Code",
            bundlePath: "/Applications/Visual Studio Code.app"
        )

        let apps = [
            hostApp,
            nestedAppEx,
            nestedMiniProgram,
            ordinaryZeroWindowApp
        ]
        let filteredApps = RuntimeAppDirectory(apps: apps).filterAppLayerCandidates(
            windowStatsByPID: [
                hostApp.processIdentifier: RuntimeAppWindowStats(windowCount: 3, hasVisibleWindow: true)
            ],
            hideMinimizedAppsFromAppLayer: false
        )

        XCTAssertEqual(
            filteredApps.compactMap(\.bundleIdentifier),
            [
                "com.tencent.xinWeChat",
                "com.microsoft.VSCode"
            ]
        )
    }

    func testAppLayerKeepsNestedAppsWhenTheyHaveWindows() {
        let hostApp = FakeRunningApplication(
            pid: 10,
            bundleIdentifier: "com.example.host",
            localizedName: "Host",
            bundlePath: "/Applications/Host.app"
        )
        let nestedApp = FakeRunningApplication(
            pid: 11,
            bundleIdentifier: "com.example.host.Helper",
            localizedName: "Host Helper",
            bundlePath: "/Applications/Host.app/Contents/Helpers/Host Helper.app"
        )

        let apps = [
            hostApp,
            nestedApp
        ]
        let filteredApps = RuntimeAppDirectory(apps: apps).filterAppLayerCandidates(
            windowStatsByPID: [
                hostApp.processIdentifier: RuntimeAppWindowStats(windowCount: 1, hasVisibleWindow: true),
                nestedApp.processIdentifier: RuntimeAppWindowStats(windowCount: 1, hasVisibleWindow: true)
            ],
            hideMinimizedAppsFromAppLayer: false
        )

        XCTAssertEqual(
            filteredApps.compactMap(\.bundleIdentifier),
            [
                "com.example.host",
                "com.example.host.Helper"
            ]
        )
    }

    func testFastAppLayerHidesNestedAppsWhenLightweightStatsOmitZeroWindowRows() {
        let hostApp = FakeRunningApplication(
            pid: 10,
            bundleIdentifier: "com.tencent.xinWeChat",
            localizedName: "WeChat",
            bundlePath: "/Applications/WeChat.app"
        )
        let nestedAppEx = FakeRunningApplication(
            pid: 11,
            bundleIdentifier: "com.tencent.flue.WeChatAppEx",
            localizedName: "WeChat",
            bundlePath: "/Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app"
        )
        let nestedMiniProgram = FakeRunningApplication(
            pid: 12,
            bundleIdentifier: "com.tencent.flue.WeApp",
            localizedName: "Mini Program",
            bundlePath: "/Applications/WeChat.app/Contents/MacOS/WeChatAppEx.app/Contents/Frameworks/WeChatAppEx Framework.framework/Versions/C/Helpers/WeApp.app"
        )
        let ordinaryZeroWindowApp = FakeRunningApplication(
            pid: 20,
            bundleIdentifier: "com.flowtab.mock.top-level-zero-window",
            localizedName: "Mock Top Level Zero Window",
            bundlePath: "/Applications/Mock Top Level Zero Window.app"
        )

        let apps = [
            hostApp,
            nestedAppEx,
            nestedMiniProgram,
            ordinaryZeroWindowApp
        ]
        let filteredApps = RuntimeAppDirectory(apps: apps).filterAppLayerCandidates(
            windowStatsByPID: [
                hostApp.processIdentifier: RuntimeAppWindowStats(windowCount: 3, hasVisibleWindow: true)
            ],
            hideMinimizedAppsFromAppLayer: false
        )

        XCTAssertEqual(
            filteredApps.compactMap(\.bundleIdentifier),
            [
                "com.tencent.xinWeChat",
                "com.flowtab.mock.top-level-zero-window"
            ]
        )
    }

    func testFastAppLayerKeepsNestedAppsWhenLightweightStatsReportWindows() {
        let hostApp = FakeRunningApplication(
            pid: 10,
            bundleIdentifier: "com.example.host",
            localizedName: "Host",
            bundlePath: "/Applications/Host.app"
        )
        let nestedApp = FakeRunningApplication(
            pid: 11,
            bundleIdentifier: "com.example.host.Helper",
            localizedName: "Host Helper",
            bundlePath: "/Applications/Host.app/Contents/Helpers/Host Helper.app"
        )

        let apps = [
            hostApp,
            nestedApp
        ]
        let filteredApps = RuntimeAppDirectory(apps: apps).filterAppLayerCandidates(
            windowStatsByPID: [
                hostApp.processIdentifier: RuntimeAppWindowStats(windowCount: 1, hasVisibleWindow: true),
                nestedApp.processIdentifier: RuntimeAppWindowStats(windowCount: 1, hasVisibleWindow: true)
            ],
            hideMinimizedAppsFromAppLayer: false
        )

        XCTAssertEqual(
            filteredApps.compactMap(\.bundleIdentifier),
            [
                "com.example.host",
                "com.example.host.Helper"
            ]
        )
    }

    func testRuntimeAppDirectorySelectsPrimaryAppsByWindowStatsBeforeRank() {
        let primaryWithWindows = FakeRunningApplication(
            pid: 20,
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor",
            bundlePath: "/Applications/Editor.app"
        )
        let rankPreferredHelper = FakeRunningApplication(
            pid: 90,
            bundleIdentifier: "com.example.editor",
            localizedName: "Editor Helper",
            bundlePath: "/Applications/Editor.app/Contents/Helpers/Editor Helper.app"
        )
        let otherApp = FakeRunningApplication(
            pid: 40,
            bundleIdentifier: "com.example.viewer",
            localizedName: "Viewer",
            bundlePath: "/Applications/Viewer.app"
        )

        let directory = RuntimeAppDirectory(apps: [rankPreferredHelper, primaryWithWindows, otherApp])
        let windowStatsByPID: [pid_t: RuntimeAppWindowStats] = [
            primaryWithWindows.processIdentifier: RuntimeAppWindowStats(windowCount: 2, hasVisibleWindow: true),
            rankPreferredHelper.processIdentifier: RuntimeAppWindowStats(windowCount: 0, hasVisibleWindow: false),
            otherApp.processIdentifier: RuntimeAppWindowStats(windowCount: 1, hasVisibleWindow: true)
        ]
        let rankByPID: [pid_t: Int] = [
            rankPreferredHelper.processIdentifier: 0,
            primaryWithWindows.processIdentifier: 8,
            otherApp.processIdentifier: 3
        ]

        let selectedApps = directory.selectPrimaryApps(
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        )
        let windowsByPID: [pid_t: [String]] = [
            primaryWithWindows.processIdentifier: ["primary-1", "primary-2"],
            rankPreferredHelper.processIdentifier: [],
            otherApp.processIdentifier: ["viewer-1"]
        ]
        let statsFromWindows = RuntimeAppDirectory.windowStats(
            for: [rankPreferredHelper, primaryWithWindows, otherApp],
            windowsByPID: windowsByPID,
            isVisibleWindow: { _ in true }
        )
        let sortedEditorGroup = directory.sortedAppsWithinGroup(
            [rankPreferredHelper, primaryWithWindows],
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        )
        let mergedEditorWindows = directory.mergedWindows(
            for: [rankPreferredHelper, primaryWithWindows],
            windowsByPID: windowsByPID,
            windowStatsByPID: statsFromWindows,
            rankByPID: rankByPID
        )
        let selectedEntries = RuntimeAppDirectory.selectPrimaryEntries(
            from: [
                RuntimeAppDirectoryEntry(
                    pid: rankPreferredHelper.processIdentifier,
                    appID: "com.example.editor",
                    bundleIdentifier: "com.example.editor",
                    localizedName: "Editor Helper",
                    launchDate: rankPreferredHelper.launchDate
                ),
                RuntimeAppDirectoryEntry(
                    pid: primaryWithWindows.processIdentifier,
                    appID: "com.example.editor",
                    bundleIdentifier: "com.example.editor",
                    localizedName: "Editor",
                    launchDate: primaryWithWindows.launchDate
                )
            ],
            windowStatsByPID: windowStatsByPID,
            rankByPID: rankByPID
        )

        XCTAssertTrue(selectedApps.contains { $0 === primaryWithWindows })
        XCTAssertTrue(selectedApps.contains { $0 === otherApp })
        XCTAssertFalse(selectedApps.contains { $0 === rankPreferredHelper })
        XCTAssertEqual(statsFromWindows[primaryWithWindows.processIdentifier]?.windowCount, 2)
        XCTAssertEqual(statsFromWindows[rankPreferredHelper.processIdentifier]?.windowCount, 0)
        XCTAssertTrue(sortedEditorGroup.first === primaryWithWindows)
        XCTAssertEqual(mergedEditorWindows, ["primary-1", "primary-2"])
        XCTAssertEqual(selectedEntries.map(\.pid), [primaryWithWindows.processIdentifier])
        XCTAssertEqual(
            directory.preferredRank(
                for: [rankPreferredHelper, primaryWithWindows],
                rankByPID: rankByPID,
                fallback: 10_000
            ),
            0
        )
        XCTAssertEqual(RuntimeAppDirectory.stableLastActiveValue(forRank: 3), -3)
        XCTAssertEqual(RuntimeAppDirectory.stableLastActiveValue(forRank: -2), 0)
    }

    func testRuntimeAppDirectoryFactSourceFiltersAppLayerRunningApplications() {
        let visibleApp = FakeRunningApplication(
            pid: 20,
            bundleIdentifier: "com.example.visible",
            localizedName: "Visible",
            bundlePath: "/Applications/Visible.app"
        )
        let accessoryApp = FakeRunningApplication(
            pid: 30,
            bundleIdentifier: "com.example.accessory",
            localizedName: "Accessory",
            bundlePath: "/Applications/Accessory.app",
            activationPolicy: .accessory
        )
        let terminatedApp = FakeRunningApplication(
            pid: 40,
            bundleIdentifier: "com.example.terminated",
            localizedName: "Terminated",
            bundlePath: "/Applications/Terminated.app",
            isTerminated: true
        )
        let currentProcessApp = FakeRunningApplication(
            pid: 50,
            bundleIdentifier: "com.example.current",
            localizedName: "Current",
            bundlePath: "/Applications/Current.app"
        )
        let runningApps = [visibleApp, accessoryApp, terminatedApp, currentProcessApp]

        XCTAssertEqual(
            RuntimeAppDirectoryFactSource.appLayerRunningApplications(
                from: runningApps,
                currentPID: currentProcessApp.processIdentifier,
                includeCurrentProcessInAppLayer: false
            ).map(\.processIdentifier),
            [visibleApp.processIdentifier]
        )
        XCTAssertEqual(
            RuntimeAppDirectoryFactSource.appLayerRunningApplications(
                from: runningApps,
                currentPID: currentProcessApp.processIdentifier,
                includeCurrentProcessInAppLayer: true
            ).map(\.processIdentifier),
            [visibleApp.processIdentifier, currentProcessApp.processIdentifier]
        )
        XCTAssertEqual(
            RuntimeAppDirectoryFactSource.entries(from: [visibleApp]).map(\.appID),
            ["com.example.visible"]
        )
    }

    func testFocusedRepairScopesCollectionToEveryRunningPIDWithTheSameAppIdentity() {
        let mainApp = FakeRunningApplication(
            pid: 6_520,
            bundleIdentifier: "com.example.multi-process",
            localizedName: "Multi Process",
            bundlePath: "/Applications/Multi Process.app"
        )
        let transientApp = FakeRunningApplication(
            pid: 83_885,
            bundleIdentifier: "com.example.multi-process",
            localizedName: "Multi Process Helper",
            bundlePath:
                "/Applications/Multi Process.app/Contents/Helpers/Helper.app"
        )
        let unrelatedApp = FakeRunningApplication(
            pid: 56_956,
            bundleIdentifier: "com.example.unrelated",
            localizedName: "Unrelated",
            bundlePath: "/Applications/Unrelated.app"
        )

        XCTAssertEqual(
            RuntimeProjectionRepairFactSource.focusedAppGroup(
                for: transientApp,
                in: [unrelatedApp, transientApp, mainApp]
            ).map(\.processIdentifier),
            [transientApp.processIdentifier, mainApp.processIdentifier]
        )
    }
}

private final class FakeRunningApplication: NSRunningApplication {
    private let fakePID: pid_t
    private let fakeBundleIdentifier: String
    private let fakeLocalizedName: String
    private let fakeBundleURL: URL
    private let fakeActivationPolicy: NSApplication.ActivationPolicy
    private let fakeIsTerminated: Bool

    init(
        pid: pid_t,
        bundleIdentifier: String,
        localizedName: String,
        bundlePath: String,
        activationPolicy: NSApplication.ActivationPolicy = .regular,
        isTerminated: Bool = false
    ) {
        fakePID = pid
        fakeBundleIdentifier = bundleIdentifier
        fakeLocalizedName = localizedName
        fakeBundleURL = URL(fileURLWithPath: bundlePath)
        fakeActivationPolicy = activationPolicy
        fakeIsTerminated = isTerminated
        super.init()
    }

    override var processIdentifier: pid_t {
        fakePID
    }

    override var activationPolicy: NSApplication.ActivationPolicy {
        fakeActivationPolicy
    }

    override var isTerminated: Bool {
        fakeIsTerminated
    }

    override var bundleIdentifier: String? {
        fakeBundleIdentifier
    }

    override var localizedName: String? {
        fakeLocalizedName
    }

    override var bundleURL: URL? {
        fakeBundleURL
    }

    override var launchDate: Date? {
        Date(timeIntervalSince1970: TimeInterval(fakePID))
    }
}
