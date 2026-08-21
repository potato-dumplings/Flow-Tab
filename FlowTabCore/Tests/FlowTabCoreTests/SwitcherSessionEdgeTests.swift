import XCTest
@testable import FlowTabCore

final class SwitcherSessionEdgeTests: XCTestCase {
    func testStartsFromLastAppOnBackwardTrigger() {
        let session = SwitcherSession(
            apps: sampleAppsWithSharedGroup(),
            triggerDirection: .backward
        )

        XCTAssertEqual(session.selectedApp.id, "com.example.Browser")
    }

    func testAppCycleNavigationClampsAtEdgesWhenWrappingDisabled() {
        var preferences = SwitcherPreferences.default
        preferences.groupNavigationWraps = false

        var session = SwitcherSession(
            apps: sampleAppsWithSharedGroup(),
            preferences: preferences,
            triggerDirection: .backward
        )

        XCTAssertEqual(session.selectedApp.id, "com.example.Browser")

        session.handle(.rightArrow)
        XCTAssertEqual(session.selectedApp.id, "com.example.Browser")

        session.handle(.leftArrow)
        XCTAssertEqual(session.selectedApp.id, "com.example.Terminal")

        session.handle(.leftArrow)
        XCTAssertEqual(session.selectedApp.id, "com.example.Editor")

        session.handle(.leftArrow)
        XCTAssertEqual(session.selectedApp.id, "com.example.Editor")
    }

    func testTabInGroupCycleMovesWithinCurrentGroup() {
        var session = SwitcherSession(apps: sampleAppsWithSharedGroup())

        XCTAssertEqual(session.selectedApp.id, "com.example.Terminal")

        session.handle(.upArrow)
        XCTAssertEqual(session.mode, .groupCycle)

        session.handle(.tabForward)
        XCTAssertEqual(session.selectedApp.id, "com.example.Editor")

        session.handle(.tabBackward)
        XCTAssertEqual(session.selectedApp.id, "com.example.Terminal")
    }

    func testGroupCycleLeftRightChangesGroupsAndSelectsFirstAppInGroup() {
        var preferences = SwitcherPreferences.default
        preferences.groupNavigationWraps = false

        var session = SwitcherSession(
            apps: sampleAppsWithSharedGroup(),
            preferences: preferences
        )

        session.handle(.upArrow)
        XCTAssertEqual(session.mode, .groupCycle)
        XCTAssertEqual(session.selectedApp.id, "com.example.Terminal")

        session.handle(.rightArrow)
        XCTAssertEqual(session.selectedGroupIndex, 1)
        XCTAssertEqual(session.selectedApp.id, "com.example.Browser")

        session.handle(.leftArrow)
        XCTAssertEqual(session.selectedGroupIndex, 0)
        XCTAssertEqual(session.selectedApp.id, "com.example.Editor")
    }

    func testCommitSelectionReturnsAppWhenSelectedAppHasNoWindows() {
        var session = SwitcherSession(
            apps: [
                AppSwitchCandidate(
                    id: "com.example.Empty",
                    displayName: "Empty",
                    groupID: "misc",
                    lastActiveAt: 1,
                    windows: []
                )
            ]
        )

        XCTAssertEqual(session.commitSelection(), .app(appID: "com.example.Empty"))
    }

    func testCommitInWindowCycleReturnsWindowAndStoresRememberedWindowID() {
        var session = SwitcherSession(
            apps: [
                AppSwitchCandidate(
                    id: "com.example.Terminal",
                    displayName: "Terminal",
                    groupID: "dev",
                    lastActiveAt: 1,
                    windows: [
                        WindowCandidate(id: "term-min", title: "Build", isMinimized: true, lastActiveAt: 50),
                        WindowCandidate(id: "term-normal", title: "Shell", isMinimized: false, lastActiveAt: 40)
                    ]
                )
            ]
        )

        XCTAssertTrue(session.enterWindowCycle(allowSingleWindow: true))
        XCTAssertEqual(session.selectedWindow?.id, "term-min")

        let target = session.commitSelection()

        XCTAssertEqual(
            target,
            .window(
                appID: "com.example.Terminal",
                windowID: "term-min",
                restoreIfMinimized: true
            )
        )
        XCTAssertEqual(session.rememberedWindowIDByAppID["com.example.Terminal"], "term-min")
    }

    func testRememberStrategyFallsBackToMostRecentWhenRememberedWindowIsMissing() {
        var preferences = SwitcherPreferences.default
        preferences.windowSwitchingStrategy = .rememberLastSelectedWindow

        var session = SwitcherSession(
            apps: [
                AppSwitchCandidate(
                    id: "com.example.Terminal",
                    displayName: "Terminal",
                    groupID: "dev",
                    lastActiveAt: 1,
                    windows: [
                        WindowCandidate(id: "term-older", title: "Logs", isMinimized: false, lastActiveAt: 10),
                        WindowCandidate(id: "term-newer", title: "Shell", isMinimized: false, lastActiveAt: 20)
                    ]
                )
            ],
            preferences: preferences,
            rememberedWindowIDByAppID: ["com.example.Terminal": "missing-window"]
        )

        XCTAssertEqual(
            session.commitSelection(),
            .app(
                appID: "com.example.Terminal",
                fallback: AppActivationFallback(
                    windowID: "term-newer",
                    restoreIfMinimized: false
                )
            )
        )
    }

    func testReleasePrimaryModifierReturnsActivationTarget() {
        var session = SwitcherSession(
            apps: [
                AppSwitchCandidate(
                    id: "com.example.Terminal",
                    displayName: "Terminal",
                    groupID: "dev",
                    lastActiveAt: 1,
                    windows: [
                        WindowCandidate(id: "term-1", title: "Shell", isMinimized: false, lastActiveAt: 20)
                    ]
                )
            ]
        )

        XCTAssertEqual(
            session.releasePrimaryModifier(),
            .app(
                appID: "com.example.Terminal",
                fallback: AppActivationFallback(
                    windowID: "term-1",
                    restoreIfMinimized: false
                )
            )
        )
    }

    func testSelectionAPIsReturnFalseForUnknownIDs() {
        var session = SwitcherSession(apps: sampleAppsWithSharedGroup())
        let initialSelection = session.selectedApp.id

        XCTAssertFalse(session.selectApp(withID: "com.example.Unknown"))
        XCTAssertFalse(session.selectWindow(appID: "com.example.Editor", windowID: "missing-window"))
        XCTAssertEqual(session.selectedApp.id, initialSelection)
    }

    func testEmptySessionDoesNotProduceActivationTarget() {
        var session = SwitcherSession(apps: [])

        session.handle(.tabForward)

        XCTAssertNil(session.commitSelection())
        XCTAssertNil(session.releasePrimaryModifier())
        XCTAssertFalse(session.selectApp(withID: "any"))
        XCTAssertFalse(session.selectWindow(appID: "any", windowID: "any"))
    }

    private func sampleAppsWithSharedGroup() -> [AppSwitchCandidate] {
        [
            AppSwitchCandidate(
                id: "com.example.Editor",
                displayName: "Editor",
                groupID: "dev",
                lastActiveAt: 300,
                windows: [
                    WindowCandidate(id: "editor-1", title: "Project", isMinimized: false, lastActiveAt: 300)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.Terminal",
                displayName: "Terminal",
                groupID: "dev",
                lastActiveAt: 200,
                windows: [
                    WindowCandidate(id: "terminal-1", title: "Shell", isMinimized: false, lastActiveAt: 200),
                    WindowCandidate(id: "terminal-2", title: "Logs", isMinimized: false, lastActiveAt: 100)
                ]
            ),
            AppSwitchCandidate(
                id: "com.example.Browser",
                displayName: "Browser",
                groupID: "web",
                lastActiveAt: 100,
                windows: [
                    WindowCandidate(id: "browser-1", title: "Docs", isMinimized: false, lastActiveAt: 100)
                ]
            )
        ]
    }
}
