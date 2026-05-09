import XCTest
@testable import FlowTabCore

final class SwitcherSessionTests: XCTestCase {
    func testStartsFromSecondAppOnForwardTrigger() {
        let session = SwitcherSession(
            apps: sampleApps(),
            triggerDirection: .forward
        )

        XCTAssertEqual(session.selectedApp.id, "com.apple.Terminal")
    }

    func testLeftRightCyclesAppsInAppCycle() {
        var session = SwitcherSession(apps: sampleApps())

        XCTAssertEqual(session.selectedApp.id, "com.apple.Terminal")

        session.handle(.rightArrow)
        XCTAssertEqual(session.selectedApp.id, "com.apple.Finder")

        session.handle(.leftArrow)
        XCTAssertEqual(session.selectedApp.id, "com.apple.Terminal")
    }

    func testUpThenLeftRightNavigatesGroups() {
        var session = SwitcherSession(apps: sampleApps())

        session.handle(.upArrow)
        XCTAssertEqual(session.mode, .groupCycle)

        session.handle(.rightArrow)
        XCTAssertEqual(session.selectedApp.id, "com.apple.Finder")

        session.handle(.leftArrow)
        XCTAssertEqual(session.selectedApp.id, "com.apple.Terminal")
    }

    func testEnterWindowLayerAndTabCyclesWindows() {
        var session = SwitcherSession(apps: sampleApps())

        session.enterWindowCycleIfPossible()
        XCTAssertEqual(session.mode, .windowCycle(appID: "com.apple.Terminal"))
        XCTAssertEqual(session.selectedWindow?.id, "term-2")

        session.handle(.tabForward)
        XCTAssertEqual(session.selectedWindow?.id, "term-1")
    }

    func testLeftRightCyclesWindowsInWindowLayer() {
        var session = SwitcherSession(apps: sampleApps())

        session.enterWindowCycleIfPossible()
        XCTAssertEqual(session.selectedWindow?.id, "term-2")

        session.handle(.leftArrow)
        XCTAssertEqual(session.selectedWindow?.id, "term-1")

        session.handle(.rightArrow)
        XCTAssertEqual(session.selectedWindow?.id, "term-2")
    }

    func testEnterWindowLayerRequiresAtLeastTwoWindows() {
        var session = SwitcherSession(apps: sampleApps(), triggerDirection: .backward)

        XCTAssertEqual(session.selectedApp.id, "com.apple.Finder")
        XCTAssertEqual(session.mode, .appCycle)

        session.enterWindowCycleIfPossible()
        XCTAssertEqual(session.mode, .appCycle)
        XCTAssertNil(session.selectedWindow)
    }

    func testForceEnterWindowLayerAllowsSingleWindow() {
        var session = SwitcherSession(apps: sampleApps(), triggerDirection: .backward)

        XCTAssertEqual(session.selectedApp.id, "com.apple.Finder")
        XCTAssertEqual(session.mode, .appCycle)

        let entered = session.enterWindowCycle(allowSingleWindow: true)

        XCTAssertTrue(entered)
        XCTAssertEqual(session.mode, .windowCycle(appID: "com.apple.Finder"))
        XCTAssertEqual(session.selectedWindow?.id, "find-1")
    }

    func testUpInWindowLayerReturnsToAppCycle() {
        var session = SwitcherSession(apps: sampleApps())

        session.handle(.upArrow)
        XCTAssertEqual(session.mode, .groupCycle)

        session.enterWindowCycleIfPossible()
        XCTAssertEqual(session.mode, .windowCycle(appID: "com.apple.Terminal"))

        session.handle(.upArrow)
        XCTAssertEqual(session.mode, .appCycle)
    }

    func testDownInAppCycleEntersWindowLayerWhenPossible() {
        var session = SwitcherSession(apps: sampleApps())

        XCTAssertEqual(session.mode, .appCycle)
        XCTAssertEqual(session.selectedApp.id, "com.apple.Terminal")

        session.handle(.downArrow)

        XCTAssertEqual(session.mode, .windowCycle(appID: "com.apple.Terminal"))
    }

    func testDownInAppCycleDoesNotEnterWindowLayerWhenSingleWindow() {
        var session = SwitcherSession(apps: sampleApps(), triggerDirection: .backward)

        XCTAssertEqual(session.selectedApp.id, "com.apple.Finder")
        XCTAssertEqual(session.mode, .appCycle)

        session.handle(.downArrow)

        XCTAssertEqual(session.mode, .appCycle)
    }

    func testSelectAppByIDSwitchesToAppCycle() {
        var session = SwitcherSession(apps: sampleApps())

        session.enterWindowCycleIfPossible()
        XCTAssertEqual(session.mode, .windowCycle(appID: "com.apple.Terminal"))

        let selected = session.selectApp(withID: "com.apple.Finder")

        XCTAssertTrue(selected)
        XCTAssertEqual(session.mode, .appCycle)
        XCTAssertEqual(session.selectedApp.id, "com.apple.Finder")
    }

    func testSelectWindowByIDSwitchesToWindowCycle() {
        var session = SwitcherSession(apps: sampleApps(), triggerDirection: .backward)
        XCTAssertEqual(session.selectedApp.id, "com.apple.Finder")

        let selected = session.selectWindow(
            appID: "com.apple.Terminal",
            windowID: "term-1"
        )

        XCTAssertTrue(selected)
        XCTAssertEqual(session.mode, .windowCycle(appID: "com.apple.Terminal"))
        XCTAssertEqual(session.selectedApp.id, "com.apple.Terminal")
        XCTAssertEqual(session.selectedWindow?.id, "term-1")
    }

    func testSelectedWindowCommitsExactWindowTarget() {
        var session = SwitcherSession(apps: sampleApps(), triggerDirection: .backward)

        XCTAssertTrue(session.selectWindow(appID: "com.apple.Terminal", windowID: "term-2"))

        let target = session.commitSelection()

        XCTAssertEqual(
            target,
            .window(appID: "com.apple.Terminal", windowID: "term-2", restoreIfMinimized: false)
        )
    }

    func testCommitDoesNotRestoreMinimizedWindowWhenDisabled() {
        var preferences = SwitcherPreferences.default
        preferences.autoRestoreMinimizedWindowOnSwitch = false
        preferences.windowSwitchingStrategy = .rememberLastSelectedWindow

        var session = SwitcherSession(
            apps: sampleApps(),
            preferences: preferences,
            rememberedWindowIDByAppID: ["com.apple.Terminal": "term-1"]
        )

        let target = session.commitSelection()
        XCTAssertEqual(target, .app(appID: "com.apple.Terminal"))
    }

    func testRemembersWindowAcrossSessions() {
        var preferences = SwitcherPreferences.default
        preferences.windowSwitchingStrategy = .rememberLastSelectedWindow

        var firstSession = SwitcherSession(apps: sampleApps(), preferences: preferences)
        firstSession.enterWindowCycleIfPossible()
        firstSession.handle(.tabForward)
        _ = firstSession.commitSelection()

        var secondSession = SwitcherSession(
            apps: sampleApps(),
            preferences: preferences,
            rememberedWindowIDByAppID: firstSession.rememberedWindowIDByAppID
        )
        let target: ActivationTarget? = secondSession.commitSelection()
        XCTAssertEqual(
            target,
            ActivationTarget.window(
                appID: "com.apple.Terminal",
                windowID: "term-1",
                restoreIfMinimized: true
            )
        )
    }

    private func sampleApps() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.apple.Safari",
                displayName: "Safari",
                groupID: "web",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(id: "saf-1", title: "Docs", isMinimized: false, lastActiveAt: 300)
                ]
            ),
            AppSwitchCandidate(
                id: "com.apple.Terminal",
                displayName: "Terminal",
                groupID: "dev",
                lastActiveAt: 200,
                windows: [
                    WindowCandidate(id: "term-1", title: "Build Logs", isMinimized: true, lastActiveAt: 80),
                    WindowCandidate(id: "term-2", title: "Shell", isMinimized: false, lastActiveAt: 220)
                ]
            ),
            AppSwitchCandidate(
                id: "com.apple.Finder",
                displayName: "Finder",
                groupID: "files",
                lastActiveAt: 100,
                windows: [
                    WindowCandidate(id: "find-1", title: "Downloads", isMinimized: false, lastActiveAt: 100)
                ]
            )
        ]
    }
}
