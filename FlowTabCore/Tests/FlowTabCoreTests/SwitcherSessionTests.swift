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

    func testUpThenLeftRightNavigatesGroups() {
        var session = SwitcherSession(apps: sampleApps())

        session.handle(.upArrow)
        XCTAssertEqual(session.mode, .groupCycle)

        session.handle(.rightArrow)
        XCTAssertEqual(session.selectedApp.id, "com.apple.Finder")

        session.handle(.leftArrow)
        XCTAssertEqual(session.selectedApp.id, "com.apple.Terminal")
    }

    func testDownEntersWindowLayerAndTabCyclesWindows() {
        var session = SwitcherSession(apps: sampleApps())

        session.handle(.downArrow)
        XCTAssertEqual(session.mode, .windowCycle(appID: "com.apple.Terminal"))
        XCTAssertEqual(session.selectedWindow?.id, "term-2")

        session.handle(.tabForward)
        XCTAssertEqual(session.selectedWindow?.id, "term-1")
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
        firstSession.handle(.downArrow)
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

    func testAutoEnterWindowLayerStrategy() {
        var preferences = SwitcherPreferences.default
        preferences.windowSwitchingStrategy = .autoEnterWindowLayer

        let session = SwitcherSession(apps: sampleApps(), preferences: preferences)
        XCTAssertEqual(session.mode, .windowCycle(appID: "com.apple.Terminal"))
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
