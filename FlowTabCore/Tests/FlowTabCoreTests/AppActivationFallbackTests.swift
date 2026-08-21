import XCTest
@testable import FlowTabCore

final class AppActivationFallbackTests: XCTestCase {
    func testAppCycleCommitsAppWithMostRecentWindowFallback() {
        var session = SwitcherSession(apps: [appWithTwoWindows()])

        XCTAssertEqual(
            session.commitSelection(),
            .app(
                appID: "com.example.Editor",
                fallback: AppActivationFallback(
                    windowID: "editor-newer",
                    restoreIfMinimized: false
                )
            )
        )
    }

    func testGroupCycleCommitsAppWithRememberedWindowFallback() {
        var preferences = SwitcherPreferences.default
        preferences.windowSwitchingStrategy = .rememberLastSelectedWindow
        var session = SwitcherSession(
            apps: [appWithTwoWindows()],
            preferences: preferences,
            rememberedWindowIDByAppID: ["com.example.Editor": "editor-older"]
        )
        session.handle(.upArrow)

        XCTAssertEqual(session.mode, .groupCycle)
        XCTAssertEqual(
            session.commitSelection(),
            .app(
                appID: "com.example.Editor",
                fallback: AppActivationFallback(
                    windowID: "editor-older",
                    restoreIfMinimized: false
                )
            )
        )
    }

    func testWindowCycleKeepsExactWindowTarget() {
        var session = SwitcherSession(apps: [appWithTwoWindows()])
        XCTAssertTrue(
            session.selectWindow(
                appID: "com.example.Editor",
                windowID: "editor-older"
            )
        )

        XCTAssertEqual(
            session.commitSelection(),
            .window(
                appID: "com.example.Editor",
                windowID: "editor-older",
                restoreIfMinimized: false
            )
        )
    }

    func testMinimizedFallbackRestoresWhenEnabled() {
        var preferences = SwitcherPreferences.default
        preferences.windowSwitchingStrategy = .rememberLastSelectedWindow
        var session = SwitcherSession(
            apps: [appWithMinimizedWindow()],
            preferences: preferences,
            rememberedWindowIDByAppID: ["com.example.Editor": "editor-minimized"]
        )

        XCTAssertEqual(
            session.commitSelection(),
            .app(
                appID: "com.example.Editor",
                fallback: AppActivationFallback(
                    windowID: "editor-minimized",
                    restoreIfMinimized: true
                )
            )
        )
    }

    func testMinimizedFallbackIsOmittedWhenRestoreIsDisabled() {
        var preferences = SwitcherPreferences.default
        preferences.autoRestoreMinimizedWindowOnSwitch = false
        var session = SwitcherSession(
            apps: [appWithMinimizedWindow()],
            preferences: preferences
        )

        XCTAssertEqual(
            session.commitSelection(),
            .app(appID: "com.example.Editor")
        )
    }

    func testWindowlessAppCommitsWithoutFallback() {
        var session = SwitcherSession(
            apps: [
                AppSwitchCandidate(
                    id: "com.example.Empty",
                    displayName: "Empty",
                    groupID: "utility",
                    lastActiveAt: 1,
                    windows: []
                )
            ]
        )

        XCTAssertEqual(
            session.commitSelection(),
            .app(appID: "com.example.Empty")
        )
    }

    private func appWithTwoWindows() -> AppSwitchCandidate {
        AppSwitchCandidate(
            id: "com.example.Editor",
            displayName: "Editor",
            groupID: "development",
            lastActiveAt: 30,
            windows: [
                WindowCandidate(
                    id: "editor-older",
                    title: "Older",
                    isMinimized: false,
                    lastActiveAt: 10
                ),
                WindowCandidate(
                    id: "editor-newer",
                    title: "Newer",
                    isMinimized: false,
                    lastActiveAt: 20
                )
            ]
        )
    }

    private func appWithMinimizedWindow() -> AppSwitchCandidate {
        AppSwitchCandidate(
            id: "com.example.Editor",
            displayName: "Editor",
            groupID: "development",
            lastActiveAt: 30,
            windows: [
                WindowCandidate(
                    id: "editor-minimized",
                    title: "Minimized",
                    isMinimized: true,
                    lastActiveAt: 20
                )
            ]
        )
    }
}
