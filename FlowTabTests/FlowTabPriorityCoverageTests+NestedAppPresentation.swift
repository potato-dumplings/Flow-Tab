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
}

private final class FakeRunningApplication: NSRunningApplication {
    private let fakePID: pid_t
    private let fakeBundleIdentifier: String
    private let fakeLocalizedName: String
    private let fakeBundleURL: URL

    init(
        pid: pid_t,
        bundleIdentifier: String,
        localizedName: String,
        bundlePath: String
    ) {
        fakePID = pid
        fakeBundleIdentifier = bundleIdentifier
        fakeLocalizedName = localizedName
        fakeBundleURL = URL(fileURLWithPath: bundlePath)
        super.init()
    }

    override var processIdentifier: pid_t {
        fakePID
    }

    override var activationPolicy: NSApplication.ActivationPolicy {
        .regular
    }

    override var isTerminated: Bool {
        false
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
