import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testRuntimeWindowRecencyTrackerMatchesRecordedCGWindowAcrossSnapshotOrder() {
        var now: TimeInterval = 500
        let tracker = RuntimeWindowRecencyTracker(clock: { now })
        let currentApp = NSRunningApplication.current
        let appID = "com.example.fixture.chrome"
        let normalFrame = CGRect(x: 120, y: 120, width: 1_100, height: 800)
        let incognitoFrame = CGRect(x: 180, y: 160, width: 1_100, height: 800)
        let windows = [
            WindowCandidate(
                id: "incognito",
                title: "Chrome Incognito Tab",
                isMinimized: false,
                lastActiveAt: 40
            ),
            WindowCandidate(
                id: "normal",
                title: "Chrome Normal Tab",
                isMinimized: false,
                lastActiveAt: 30
            )
        ]
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                "incognito": RuntimeWindowContext(
                    id: "incognito",
                    title: "Chrome Incognito Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 167_047,
                    frame: incognitoFrame
                ),
                "normal": RuntimeWindowContext(
                    id: "normal",
                    title: "Chrome Normal Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 167_044,
                    frame: normalFrame
                )
            ]
        )

        now = 900
        tracker.record(
            appID: appID,
            windowID: "old-runtime-id",
            ownerPID: currentApp.processIdentifier,
            cgWindowID: 167_044,
            title: "Chrome Normal Tab",
            frame: normalFrame
        )

        let updatedSnapshot = tracker.snapshotWithRecencyApplied(
            RuntimeSnapshot(
                apps: [
                    AppSwitchCandidate(
                        id: appID,
                        displayName: "Chrome Fixture",
                        groupID: "chrome",
                        lastActiveAt: 100,
                        windows: windows
                    )
                ],
                contextsByID: [appID: context]
            )
        )
        var session = SwitcherSession(apps: updatedSnapshot.apps)

        XCTAssertTrue(session.enterWindowCycle(allowSingleWindow: true))
        XCTAssertEqual(session.selectedWindow?.id, "normal")
    }

    func testRuntimeWindowRecencyTrackerOrdersRecordedWindowsBeforeFallbackInRecencyOrder() {
        var now: TimeInterval = 500
        let tracker = RuntimeWindowRecencyTracker(clock: { now })
        let currentApp = NSRunningApplication.current
        let appID = "com.example.fixture.chrome"
        let windows = [
            WindowCandidate(id: "incognito", title: "Chrome Incognito Tab", isMinimized: false, lastActiveAt: 40),
            WindowCandidate(id: "second-fullscreen", title: "Chrome Second Fullscreen Tab", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "fullscreen", title: "Chrome Fullscreen Tab", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "normal", title: "Chrome Normal Tab", isMinimized: false, lastActiveAt: 10)
        ]
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: Dictionary(uniqueKeysWithValues: windows.enumerated().map { index, window in
                (
                    window.id,
                    RuntimeWindowContext(
                        id: window.id,
                        title: window.title,
                        isMinimized: false,
                        ownerPID: currentApp.processIdentifier,
                        cgWindowID: CGWindowID(170_000 + index)
                    )
                )
            })
        )

        now = 800
        tracker.record(appID: appID, windowID: "fullscreen", context: context)
        now = 900
        tracker.record(appID: appID, windowID: "normal", context: context)

        let updatedSnapshot = tracker.snapshotWithRecencyApplied(
            RuntimeSnapshot(
                apps: [
                    AppSwitchCandidate(
                        id: appID,
                        displayName: "Chrome Fixture",
                        groupID: "chrome",
                        lastActiveAt: 100,
                        windows: windows
                    )
                ],
                contextsByID: [appID: context]
            )
        )

        XCTAssertEqual(
            updatedSnapshot.apps.first?.windows.map(\.id),
            ["normal", "fullscreen", "incognito", "second-fullscreen"]
        )
    }

    @MainActor
    func testLiveSwitcherModelGlobalSnapshotRecencyUsesOnlySelectedAppsOwnWindowEvidence() {
        let model = LiveSwitcherModel()
        let currentApp = NSRunningApplication.current
        let currentAppID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let otherAppID = "com.example.other"
        let currentFocusedFrame = CGRect(x: 120, y: 120, width: 1_100, height: 800)
        let currentZOrderFrame = CGRect(x: 180, y: 160, width: 1_100, height: 800)
        let otherNewFrame = CGRect(x: 200, y: 180, width: 1_000, height: 700)
        let otherOldFrame = CGRect(x: 240, y: 220, width: 1_000, height: 700)
        let currentWindows = [
            WindowCandidate(
                id: "current-zorder",
                title: "Current Z Order",
                isMinimized: false,
                lastActiveAt: 40
            ),
            WindowCandidate(
                id: "current-focused",
                title: "Current Focused",
                isMinimized: false,
                lastActiveAt: 30
            )
        ]
        let otherWindows = [
            WindowCandidate(
                id: "other-new",
                title: "Other New",
                isMinimized: false,
                lastActiveAt: 90
            ),
            WindowCandidate(
                id: "other-old",
                title: "Other Old",
                isMinimized: false,
                lastActiveAt: 80
            )
        ]
        let currentContext = RuntimeAppContext(
            appID: currentAppID,
            runningApp: currentApp,
            windowsByID: [
                "current-zorder": RuntimeWindowContext(
                    id: "current-zorder",
                    title: "Current Z Order",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 10,
                    frame: currentZOrderFrame
                ),
                "current-focused": RuntimeWindowContext(
                    id: "current-focused",
                    title: "Current Focused",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 11,
                    frame: currentFocusedFrame
                )
            ]
        )
        let otherContext = RuntimeAppContext(
            appID: otherAppID,
            runningApp: currentApp,
            windowsByID: [
                "other-new": RuntimeWindowContext(
                    id: "other-new",
                    title: "Other New",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 20,
                    frame: otherNewFrame
                ),
                "other-old": RuntimeWindowContext(
                    id: "other-old",
                    title: "Other Old",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 21,
                    frame: otherOldFrame
                )
            ]
        )

        model.frontmostApplicationOverride = { currentApp }
        model.focusedWindowIdentityOverride = { _ in
            RuntimeFocusedWindowIdentity(
                cgWindowID: 11,
                title: "Current Focused",
                frame: currentFocusedFrame
            )
        }
        model.snapshotProviderOverride = {
            RuntimeSnapshot(
                apps: [
                    AppSwitchCandidate(
                        id: currentAppID,
                        displayName: "Current",
                        groupID: "current",
                        lastActiveAt: 100,
                        windows: currentWindows
                    ),
                    AppSwitchCandidate(
                        id: otherAppID,
                        displayName: "Other",
                        groupID: "other",
                        lastActiveAt: 90,
                        windows: otherWindows
                    )
                ],
                contextsByID: [
                    currentAppID: currentContext,
                    otherAppID: otherContext
                ]
            )
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.selectedApp?.id, otherAppID)

        model.handle(.downArrow)
        XCTAssertEqual(model.session?.mode, .windowCycle(appID: otherAppID))
        XCTAssertEqual(model.session?.selectedWindow?.id, "other-new")

        model.handle(.upArrow)
        model.handle(.tabForward)
        XCTAssertEqual(model.selectedApp?.id, currentAppID)

        model.handle(.downArrow)
        XCTAssertEqual(model.session?.mode, .windowCycle(appID: currentAppID))
        XCTAssertEqual(model.session?.selectedWindow?.id, "current-focused")
    }

    @MainActor
    func testLiveSwitcherModelRecordsFrontmostRuntimeWindowWhenAXFocusedWindowUnavailable() {
        let model = LiveSwitcherModel()
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let initialWindows = [
            WindowCandidate(id: "fullscreen", title: "Chrome Fullscreen Tab", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "incognito", title: "Chrome Incognito Tab", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "normal", title: "Chrome Normal Tab", isMinimized: false, lastActiveAt: 10)
        ]
        let reorderedWindows = [
            WindowCandidate(id: "incognito", title: "Chrome Incognito Tab", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "fullscreen", title: "Chrome Fullscreen Tab", isMinimized: false, lastActiveAt: 20),
            WindowCandidate(id: "normal", title: "Chrome Normal Tab", isMinimized: false, lastActiveAt: 10)
        ]
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                "fullscreen": RuntimeWindowContext(
                    id: "fullscreen",
                    title: "Chrome Fullscreen Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 30
                ),
                "incognito": RuntimeWindowContext(
                    id: "incognito",
                    title: "Chrome Incognito Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 20
                ),
                "normal": RuntimeWindowContext(
                    id: "normal",
                    title: "Chrome Normal Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 10
                )
            ]
        )

        var snapshotWindows = initialWindows
        var frontmostRuntimeWindowID: String? = "fullscreen"
        model.frontmostApplicationOverride = { currentApp }
        model.focusedWindowIdentityOverride = { _ in nil }
        model.frontmostRuntimeWindowIDOverride = { _, _, _ in frontmostRuntimeWindowID }
        model.snapshotProviderOverride = {
            RuntimeSnapshot(
                apps: [
                    AppSwitchCandidate(
                        id: appID,
                        displayName: "Chrome Fixture",
                        groupID: "chrome",
                        lastActiveAt: 100,
                        windows: snapshotWindows
                    )
                ],
                contextsByID: [appID: context]
            )
        }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.session?.apps.first?.windows.map(\.id), ["fullscreen", "incognito", "normal"])

        model.windowRecencyTracker.record(appID: appID, windowID: "normal", context: context)
        frontmostRuntimeWindowID = "normal"
        snapshotWindows = reorderedWindows

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        XCTAssertEqual(model.session?.apps.first?.windows.map(\.id), ["normal", "fullscreen", "incognito"])
    }
}
