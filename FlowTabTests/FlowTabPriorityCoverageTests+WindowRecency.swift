import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    func testRuntimeWindowRecencyMatchDiagnosticIncludesConfidenceAndAction() {
        let diagnostic = RuntimeRecencyMatchDiagnostic(
            appID: "com.example.fixture",
            recordWindowID: "old-runtime-id",
            matchedWindowID: "new-runtime-id",
            confidence: .semanticTitleFrame,
            candidateCount: 1,
            ageSeconds: 42,
            recordGeneration: 3,
            evaluationGeneration: 5,
            generationAge: 2,
            action: "apply_low_confidence_ordering",
            reason: nil
        )

        XCTAssertTrue(diagnostic.logMessage.contains("event=recency_match"))
        XCTAssertTrue(diagnostic.logMessage.contains("confidence=semanticTitleFrame"))
        XCTAssertTrue(diagnostic.logMessage.contains("candidateCount=1"))
        XCTAssertTrue(diagnostic.logMessage.contains("recordGeneration=3"))
        XCTAssertTrue(diagnostic.logMessage.contains("evaluationGeneration=5"))
        XCTAssertTrue(diagnostic.logMessage.contains("generationAge=2"))
        XCTAssertTrue(diagnostic.logMessage.contains("action=apply_low_confidence_ordering"))
        XCTAssertEqual(RuntimeLogCategory.resolve("Recency"), .recency)
        XCTAssertTrue(RuntimeLogCategory.recency.isVerboseOnlyBelowWarning)
        XCTAssertEqual(RuntimeLogCategory.resolve("Projection"), .projection)
        XCTAssertTrue(RuntimeLogCategory.projection.isVerboseOnlyBelowWarning)
    }

    func testRuntimeProjectionDiagnosticsTimingLineUsesProjectionBoundaryFields() {
        XCTAssertEqual(
            RuntimeProjectionDiagnostics.timingLine(
                "fullRepairProjectionPayload",
                fields: [
                    ("result", "ready"),
                    ("apps", "3"),
                    ("totalMs", "1.25")
                ]
            ),
            "fullRepairProjectionPayload result=ready apps=3 totalMs=1.25"
        )
    }

    func testRuntimeWindowRecencyTrackerSkipsRecordWhenBindingDisallowsRecency() {
        var now: TimeInterval = 500
        let tracker = RuntimeWindowRecencyTracker(clock: { now })
        let currentApp = NSRunningApplication.current
        let appID = "com.example.fixture.chrome"
        let windows = [
            WindowCandidate(id: "first", title: "First Window", isMinimized: false, lastActiveAt: 40),
            WindowCandidate(id: "second", title: "Second Window", isMinimized: false, lastActiveAt: 30)
        ]
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                "first": RuntimeWindowContext(
                    id: "first",
                    title: "First Window",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 171_001,
                    lastConfirmationSource: .publicExactMatch
                ),
                "second": RuntimeWindowContext(
                    id: "second",
                    title: "Second Window",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 171_002,
                    lastConfirmationSource: .publicExactMatch
                )
            ]
        )

        now = 900
        tracker.record(
            appID: appID,
            windowID: "second",
            ownerPID: currentApp.processIdentifier,
            cgWindowID: 171_002,
            title: "Second Window",
            frame: nil,
            allowedActions: WindowBindingConfidence.sticky.allowedActions
        )

        let updatedApps = recencyAppliedApps(
            tracker,
            appID: appID,
            displayName: "Chrome Fixture",
            groupID: "chrome",
            windows: windows,
            context: context
        )

        XCTAssertEqual(updatedApps.first?.windows.map(\.id), ["first", "second"])
    }

    func testRuntimeWindowRecencyTrackerRecordsVerifiedFocusOnlyWhenBindingCanActivate() {
        var now: TimeInterval = 500
        let tracker = RuntimeWindowRecencyTracker(clock: { now })
        let currentApp = NSRunningApplication.current
        let appID = "com.example.fixture.verified-focus"
        let windows = [
            WindowCandidate(id: "first", title: "First Window", isMinimized: false, lastActiveAt: 40),
            WindowCandidate(id: "second", title: "Second Window", isMinimized: false, lastActiveAt: 30)
        ]
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                "first": RuntimeWindowContext(
                    id: "first",
                    title: "First Window",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 172_001,
                    lastConfirmationSource: .publicExactMatch
                ),
                "second": RuntimeWindowContext(
                    id: "second",
                    title: "Second Window",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 172_002,
                    lastConfirmationSource: .stickyBinding
                )
            ]
        )
        now = 900
        tracker.recordVerifiedFocus(
            appID: appID,
            windowID: "second",
            ownerPID: currentApp.processIdentifier,
            cgWindowID: 172_002,
            title: "Second Window",
            frame: nil,
            allowedActions: WindowBindingConfidence.provisional.allowedActions
        )
        XCTAssertEqual(
            recencyAppliedWindowIDs(
                tracker,
                appID: appID,
                displayName: "Verified Focus Fixture",
                groupID: "verified-focus",
                windows: windows,
                context: context
            ),
            ["first", "second"]
        )

        now = 1_000
        tracker.recordVerifiedFocus(
            appID: appID,
            windowID: "second",
            ownerPID: currentApp.processIdentifier,
            cgWindowID: 172_002,
            title: "Second Window",
            frame: nil,
            allowedActions: WindowBindingConfidence.sticky.allowedActions
        )

        XCTAssertEqual(
            recencyAppliedWindowIDs(
                tracker,
                appID: appID,
                displayName: "Verified Focus Fixture",
                groupID: "verified-focus",
                windows: windows,
                context: context
            ),
            ["second", "first"]
        )
    }

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

        let updatedApps = recencyAppliedApps(
            tracker,
            appID: appID,
            displayName: "Chrome Fixture",
            groupID: "chrome",
            windows: windows,
            context: context
        )
        var session = SwitcherSession(apps: updatedApps)

        XCTAssertTrue(session.enterWindowCycle(allowSingleWindow: true))
        XCTAssertEqual(session.selectedWindow?.id, "normal")
    }

    func testRuntimeWindowRecencyTrackerExpiresSemanticTitleFrameFallback() {
        var now: TimeInterval = 100
        let tracker = RuntimeWindowRecencyTracker(
            clock: { now },
            semanticFallbackMaxAge: 10
        )
        let currentApp = NSRunningApplication.current
        let appID = "com.example.fixture.semantic-recency"
        let documentFrame = CGRect(x: 120, y: 120, width: 1_100, height: 800)
        let otherFrame = CGRect(x: 240, y: 160, width: 900, height: 700)
        let windows = [
            WindowCandidate(id: "other", title: "Other Doc", isMinimized: false, lastActiveAt: 40),
            WindowCandidate(id: "new-runtime-id", title: "Recovered Doc", isMinimized: false, lastActiveAt: 30)
        ]
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                "other": RuntimeWindowContext(
                    id: "other",
                    title: "Other Doc",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 200_001,
                    frame: otherFrame
                ),
                "new-runtime-id": RuntimeWindowContext(
                    id: "new-runtime-id",
                    title: "Recovered Doc",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 200_002,
                    frame: documentFrame
                )
            ]
        )
        tracker.record(
            appID: appID,
            windowID: "old-runtime-id",
            ownerPID: currentApp.processIdentifier,
            cgWindowID: nil,
            title: "Recovered Doc",
            frame: documentFrame
        )

        now = 105
        XCTAssertEqual(
            recencyAppliedWindowIDs(
                tracker,
                appID: appID,
                displayName: "Semantic Recency Fixture",
                groupID: "semantic",
                windows: windows,
                context: context
            ),
            ["new-runtime-id", "other"]
        )

        now = 120
        XCTAssertEqual(
            recencyAppliedWindowIDs(
                tracker,
                appID: appID,
                displayName: "Semantic Recency Fixture",
                groupID: "semantic",
                windows: windows,
                context: context
            ),
            ["other", "new-runtime-id"]
        )
    }

    func testRuntimeWindowRecencyTrackerExpiresSemanticFallbackAcrossSnapshotGenerations() {
        var now: TimeInterval = 100
        let tracker = RuntimeWindowRecencyTracker(
            clock: { now },
            semanticFallbackMaxAge: 1_000,
            semanticFallbackMaxGenerationAge: 1
        )
        let currentApp = NSRunningApplication.current
        let appID = "com.example.fixture.semantic-generation-recency"
        let documentFrame = CGRect(x: 120, y: 120, width: 1_100, height: 800)
        let otherFrame = CGRect(x: 240, y: 160, width: 900, height: 700)
        let windows = [
            WindowCandidate(id: "other", title: "Other Doc", isMinimized: false, lastActiveAt: 40),
            WindowCandidate(id: "new-runtime-id", title: "Recovered Doc", isMinimized: false, lastActiveAt: 30)
        ]
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                "other": RuntimeWindowContext(
                    id: "other",
                    title: "Other Doc",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 210_001,
                    frame: otherFrame
                ),
                "new-runtime-id": RuntimeWindowContext(
                    id: "new-runtime-id",
                    title: "Recovered Doc",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 210_002,
                    frame: documentFrame
                )
            ]
        )
        tracker.record(
            appID: appID,
            windowID: "old-runtime-id",
            ownerPID: currentApp.processIdentifier,
            cgWindowID: nil,
            title: "Recovered Doc",
            frame: documentFrame
        )

        now = 105
        XCTAssertEqual(
            recencyAppliedWindowIDs(
                tracker,
                appID: appID,
                displayName: "Semantic Generation Recency Fixture",
                groupID: "semantic-generation",
                windows: windows,
                context: context
            ),
            ["new-runtime-id", "other"]
        )
        XCTAssertEqual(
            recencyAppliedWindowIDs(
                tracker,
                appID: appID,
                displayName: "Semantic Generation Recency Fixture",
                groupID: "semantic-generation",
                windows: windows,
                context: context
            ),
            ["other", "new-runtime-id"]
        )
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
                        cgWindowID: CGWindowID(170_000 + index),
                        lastConfirmationSource: .publicExactMatch
                    )
                )
            })
        )

        now = 800
        tracker.record(appID: appID, windowID: "fullscreen", context: context)
        now = 900
        tracker.record(appID: appID, windowID: "normal", context: context)

        let updatedApps = recencyAppliedApps(
            tracker,
            appID: appID,
            displayName: "Chrome Fixture",
            groupID: "chrome",
            windows: windows,
            context: context
        )

        XCTAssertEqual(
            updatedApps.first?.windows.map(\.id),
            ["normal", "fullscreen", "incognito", "second-fullscreen"]
        )
    }

    func testRuntimeWindowRecencyTrackerAppliesSameOrderingToCurrentAppPayload() {
        var now: TimeInterval = 500
        let tracker = RuntimeWindowRecencyTracker(clock: { now })
        let currentApp = NSRunningApplication.current
        let appID = "com.example.fixture.home"
        let windows = [
            WindowCandidate(id: "first", title: "First Window", isMinimized: false, lastActiveAt: 40),
            WindowCandidate(id: "second", title: "Second Window", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "third", title: "Third Window", isMinimized: false, lastActiveAt: 20)
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
                        cgWindowID: CGWindowID(180_000 + index),
                        lastConfirmationSource: .publicExactMatch
                    )
                )
            })
        )
        let payload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Home Fixture",
                groupID: "home",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: currentApp.processIdentifier
            ),
            candidate: AppSwitchCandidate(
                id: appID,
                displayName: "Home Fixture",
                groupID: "home",
                lastActiveAt: 100,
                windows: windows
            ),
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: currentApp)]
        )

        now = 800
        tracker.record(appID: appID, windowID: "second", context: context)

        let updatedPayload = tracker.currentAppWindowPayloadWithRecencyApplied(payload)

        XCTAssertEqual(
            updatedPayload.candidate.windows.map(\.id),
            ["second", "first", "third"]
        )
        XCTAssertEqual(updatedPayload.summary.windowCount, 3)
        XCTAssertEqual(updatedPayload.appDirectoryEntries, payload.appDirectoryEntries)
    }

    @MainActor
    func testLiveSwitcherModelGlobalSnapshotRecencyUsesOnlySelectedAppsOwnWindowEvidence() {
        let restoreCurrentAppVisibility = enableCurrentAppInSwitcherForTesting()
        defer { restoreCurrentAppVisibility() }

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
                    frame: currentZOrderFrame,
                    lastConfirmationSource: .publicExactMatch
                ),
                "current-focused": RuntimeWindowContext(
                    id: "current-focused",
                    title: "Current Focused",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 11,
                    frame: currentFocusedFrame,
                    lastConfirmationSource: .publicExactMatch
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
                    frame: otherNewFrame,
                    lastConfirmationSource: .publicExactMatch
                ),
                "other-old": RuntimeWindowContext(
                    id: "other-old",
                    title: "Other Old",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 21,
                    frame: otherOldFrame,
                    lastConfirmationSource: .publicExactMatch
                )
            ]
        )

        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: [
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
        let model = LiveSwitcherModel(
            windowRecencyTracker: RuntimeWindowRecencyTracker(),
            runtimeProjectionService: runtimeProjectionService
        )
        model.windowRecencyTracker.recordVerifiedFocus(
            appID: currentAppID,
            windowID: "current-focused",
            context: currentContext
        )
        model.frontmostApplicationOverride = { currentApp }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        assertAppSwitcherProjectionRead(from: runtimeProjectionService)
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
    func testLiveSwitcherModelAppliesCommittedVerifiedFocusRecencyWithoutLiveFocusedRead() {
        let model = LiveSwitcherModel(windowRecencyTracker: RuntimeWindowRecencyTracker())
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let fullscreenFrame = CGRect(x: 0, y: 37, width: 1_728, height: 1_080)
        let incognitoFrame = CGRect(x: 180, y: 160, width: 1_100, height: 800)
        let normalFrame = CGRect(x: 120, y: 120, width: 1_100, height: 800)
        let windows = [
            WindowCandidate(id: "incognito", title: "Chrome Incognito Tab", isMinimized: false, lastActiveAt: 40),
            WindowCandidate(id: "fullscreen", title: "Chrome Fullscreen Tab", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "normal", title: "Chrome Normal Tab", isMinimized: false, lastActiveAt: 20)
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
                    cgWindowID: 41,
                    frame: incognitoFrame,
                    lastConfirmationSource: .stickyBinding
                ),
                "fullscreen": RuntimeWindowContext(
                    id: "fullscreen",
                    title: "Chrome Fullscreen Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 42,
                    frame: fullscreenFrame,
                    lastConfirmationSource: .stickyBinding
                ),
                "normal": RuntimeWindowContext(
                    id: "normal",
                    title: "Chrome Normal Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 43,
                    frame: normalFrame,
                    lastConfirmationSource: .stickyBinding
                )
            ]
        )
        model.frontmostApplicationOverride = { currentApp }
        model.windowRecencyTracker.recordVerifiedFocus(
            appID: appID,
            windowID: "fullscreen",
            context: context
        )

        let updatedApps = recencyAppliedApps(
            model.windowRecencyTracker,
            appID: appID,
            displayName: "Chrome Fixture",
            groupID: "chrome",
            windows: windows,
            context: context
        )

        XCTAssertEqual(
            updatedApps.first?.windows.map(\.id),
            ["fullscreen", "incognito", "normal"]
        )
    }

    @MainActor
    func testLiveSwitcherModelFocusedRuntimeProjectionUsesCommittedRecencyBeforeOrdering() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let fullscreenFrame = CGRect(x: 0, y: 37, width: 1_728, height: 1_080)
        let incognitoFrame = CGRect(x: 180, y: 160, width: 1_100, height: 800)
        let normalFrame = CGRect(x: 120, y: 120, width: 1_100, height: 800)
        let windows = [
            WindowCandidate(id: "incognito", title: "Chrome Incognito Tab", isMinimized: false, lastActiveAt: 40),
            WindowCandidate(id: "fullscreen", title: "Chrome Fullscreen Tab", isMinimized: false, lastActiveAt: 30),
            WindowCandidate(id: "normal", title: "Chrome Normal Tab", isMinimized: false, lastActiveAt: 20)
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
                    cgWindowID: 41,
                    frame: incognitoFrame,
                    lastConfirmationSource: .stickyBinding
                ),
                "fullscreen": RuntimeWindowContext(
                    id: "fullscreen",
                    title: "Chrome Fullscreen Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 42,
                    frame: fullscreenFrame,
                    lastConfirmationSource: .stickyBinding
                ),
                "normal": RuntimeWindowContext(
                    id: "normal",
                    title: "Chrome Normal Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 43,
                    frame: normalFrame,
                    lastConfirmationSource: .stickyBinding
                )
            ]
        )
        let focusedCurrentAppWindowPayload = RuntimeCurrentAppWindowPayload(
            summary: RuntimeHomeAppSummary(
                appID: appID,
                displayName: "Chrome Fixture",
                groupID: "chrome",
                lastActiveAt: 100,
                windowCount: windows.count,
                pid: currentApp.processIdentifier
            ),
            candidate: AppSwitchCandidate(
                id: appID,
                displayName: "Chrome Fixture",
                groupID: "chrome",
                lastActiveAt: 100,
                windows: windows
            ),
            context: context,
            appDirectoryEntries: [RuntimeAppDirectoryEntry(app: currentApp)]
        )
        let runtimeProjectionService = RecordingRuntimeProjectionService(
            currentAppWindowProjectionsByAppID: [
                appID: RuntimeCurrentAppWindowProjection(
                    appID: appID,
                    currentAppWindowPayload: focusedCurrentAppWindowPayload,
                    freshness: RuntimeProjectionFreshness(
                        generatedAt: 12,
                        sourceGeneration: RuntimeReadModelGeneration(projection: 1),
                        dirtyAppIDs: [],
                        dirtyPIDs: [],
                        dirtyCGWindowIDs: [],
                        pendingRepairScopes: [],
                        isCompleteForScope: true
                    )
                )
            ]
        )
        let model = LiveSwitcherModel(
            windowRecencyTracker: RuntimeWindowRecencyTracker(),
            runtimeProjectionService: runtimeProjectionService
        )
        model.frontmostApplicationOverride = { currentApp }
        model.windowRecencyTracker.recordVerifiedFocus(
            appID: appID,
            windowID: "fullscreen",
            context: context
        )

        XCTAssertTrue(model.startFocusedAppWindowSession(triggerDirection: .forward))

        assertCurrentAppWindowProjectionRead(from: runtimeProjectionService, appID: appID)
        XCTAssertEqual(
            model.session?.selectedApp.windows.map(\.id),
            ["fullscreen", "incognito", "normal"]
        )
    }

    @MainActor
    func testLiveSwitcherModelAppliesCommittedRuntimeWindowRecencyWhenProjectionOrderChanges() {
        let restoreCurrentAppVisibility = enableCurrentAppInSwitcherForTesting()
        defer { restoreCurrentAppVisibility() }

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
                    cgWindowID: 30,
                    lastConfirmationSource: .publicExactMatch
                ),
                "incognito": RuntimeWindowContext(
                    id: "incognito",
                    title: "Chrome Incognito Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 20,
                    lastConfirmationSource: .publicExactMatch
                ),
                "normal": RuntimeWindowContext(
                    id: "normal",
                    title: "Chrome Normal Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 10,
                    lastConfirmationSource: .publicExactMatch
                )
            ]
        )

        let runtimeProjectionService = RecordingRuntimeProjectionService(
            appSwitcherApps: [
                AppSwitchCandidate(
                    id: appID,
                    displayName: "Chrome Fixture",
                    groupID: "chrome",
                    lastActiveAt: 100,
                    windows: initialWindows
                )
            ],
            contextsByID: [appID: context]
        )
        let model = LiveSwitcherModel(
            windowRecencyTracker: RuntimeWindowRecencyTracker(),
            runtimeProjectionService: runtimeProjectionService
        )
        model.frontmostApplicationOverride = { currentApp }

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        assertAppSwitcherProjectionRead(from: runtimeProjectionService)
        XCTAssertEqual(model.session?.apps.first?.windows.map(\.id), ["fullscreen", "incognito", "normal"])

        model.windowRecencyTracker.recordVerifiedFocus(appID: appID, windowID: "normal", context: context)
        runtimeProjectionService.installAppSwitcherProjection(
            apps: [
                AppSwitchCandidate(
                    id: appID,
                    displayName: "Chrome Fixture",
                    groupID: "chrome",
                    lastActiveAt: 100,
                    windows: reorderedWindows
                )
            ],
            contextsByID: [appID: context]
        )

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        assertAppSwitcherProjectionRead(from: runtimeProjectionService, readCount: 2)
        XCTAssertEqual(model.session?.apps.first?.windows.map(\.id), ["normal", "incognito", "fullscreen"])
    }

    @MainActor
    func testLiveSwitcherModelSignalsRuntimeWhenWindowFocusIsVerified() {
        let runtimeProjectionService = RecordingRuntimeProjectionService()
        let model = LiveSwitcherModel(
            windowRecencyTracker: RuntimeWindowRecencyTracker(),
            runtimeProjectionService: runtimeProjectionService
        )
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"

        model.activator.windowFocusVerifiedHandler?(
            RuntimeWindowFocusVerification(
                appID: appID,
                windowID: "cg:\(currentApp.processIdentifier):240001",
                ownerPID: currentApp.processIdentifier,
                targetCGWindowID: 240_001,
                focusedCGWindowID: 240_001,
                focusedAXWindow: nil,
                title: "Verified Window",
                frame: CGRect(x: 10, y: 20, width: 800, height: 600),
                allowedActions: WindowBindingConfidence.exact.allowedActions
            )
        )

        let signals = runtimeProjectionService.windowFocusVerifiedSignalsRecorded()
        XCTAssertEqual(signals.map(\.appID), [appID])
        XCTAssertEqual(signals.map(\.pid), [currentApp.processIdentifier])
        XCTAssertEqual(runtimeProjectionService.windowFocusVerificationSignalsRecorded().map(\.focusedCGWindowID), [240_001])
    }

    private func recencyAppliedWindowIDs(
        _ tracker: RuntimeWindowRecencyTracker,
        appID: String,
        displayName: String,
        groupID: String,
        windows: [WindowCandidate],
        context: RuntimeAppContext
    ) -> [String]? {
        let apps = recencyAppliedApps(
            tracker,
            appID: appID,
            displayName: displayName,
            groupID: groupID,
            windows: windows,
            context: context
        )
        return apps.first?.windows.map(\.id)
    }

    private func assertAppSwitcherProjectionRead(
        from runtimeProjectionService: RecordingRuntimeProjectionService,
        readCount: Int = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherProjectionReadCount(),
            readCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            Array(repeating: .switcherSessionStarted, count: readCount),
            file: file,
            line: line
        )
    }

    private func assertCurrentAppWindowProjectionRead(
        from runtimeProjectionService: RecordingRuntimeProjectionService,
        appID: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            runtimeProjectionService.currentAppWindowProjectionReadCount(appID: appID),
            1,
            file: file,
            line: line
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherProjectionReadCount(),
            0,
            file: file,
            line: line
        )
    }

    private func recencyAppliedApps(
        _ tracker: RuntimeWindowRecencyTracker,
        appID: String,
        displayName: String,
        groupID: String,
        windows: [WindowCandidate],
        context: RuntimeAppContext
    ) -> [AppSwitchCandidate] {
        tracker.appsWithRecencyApplied(
            [
                AppSwitchCandidate(
                    id: appID,
                    displayName: displayName,
                    groupID: groupID,
                    lastActiveAt: 100,
                    windows: windows
                )
            ],
            contextsByID: [appID: context]
        )
    }
}
