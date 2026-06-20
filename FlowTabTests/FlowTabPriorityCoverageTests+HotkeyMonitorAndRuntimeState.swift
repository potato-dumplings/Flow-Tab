import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testRuntimeAXWindowChangeMonitorRoutesKnownDestroyedAXWindowThroughTypedCallback() {
        let pid: pid_t = 18_405
        let knownWindow = AXUIElementCreateApplication(pid)
        let unrelatedWindow = AXUIElementCreateApplication(pid + 1)
        let knownWindowID = AXWindowInspectorForTesting.makeWindowID(pid: pid, index: 0)
        AXLiveWindowRegistry.shared.refreshSnapshot(forPID: pid, windows: [knownWindow])
        defer { AXLiveWindowRegistry.shared.remove(pid: pid) }

        let monitor = RuntimeAXWindowChangeMonitor()
        var destroyedEvents: [(String, pid_t, String)] = []
        var changedEvents: [(String, pid_t)] = []
        monitor.onAXWindowDestroyed = { appID, pid, axWindowID in
            destroyedEvents.append((appID, pid, axWindowID))
        }
        monitor.onAppWindowChanged = { appID, pid in
            changedEvents.append((appID, pid))
        }

        let installedAt = ProcessInfo.processInfo.systemUptime - 1
        monitor.handleAXNotification(
            appID: "com.example.editor",
            pid: pid,
            notification: kAXUIElementDestroyedNotification as CFString,
            element: knownWindow,
            installedAt: installedAt
        )
        monitor.handleAXNotification(
            appID: "com.example.editor",
            pid: pid,
            notification: kAXUIElementDestroyedNotification as CFString,
            element: unrelatedWindow,
            installedAt: installedAt
        )

        XCTAssertEqual(destroyedEvents.count, 1)
        XCTAssertEqual(destroyedEvents.first?.0, "com.example.editor")
        XCTAssertEqual(destroyedEvents.first?.1, pid)
        XCTAssertEqual(destroyedEvents.first?.2, knownWindowID)
        XCTAssertEqual(changedEvents.count, 1)
        XCTAssertEqual(changedEvents.first?.0, "com.example.editor")
        XCTAssertEqual(changedEvents.first?.1, pid)
    }

    func testOptionTabHotkeyMonitorRoutesForwardAndBackwardPressReleaseCallbacks() {
        let monitor = OptionTabHotkeyMonitor(
            configuration: SwitcherHotkeyPreferencesStore.resolve(
                primaryModifierRaw: SwitcherPrimaryModifier.option.rawValue,
                mainKeyRaw: SwitcherHotkeyKey.tab.rawValue,
                quitKeyRaw: SwitcherHotkeyKey.q.rawValue
            ),
            signature: 0x54455354,
            forwardHotkeyID: 11,
            backwardHotkeyID: 22,
            startsMonitoring: false
        )

        var events: [String] = []
        monitor.onHotkeyPressed = { isBackward in
            events.append(isBackward ? "press-backward" : "press-forward")
        }
        monitor.onHotkeyReleased = { isBackward in
            events.append(isBackward ? "release-backward" : "release-forward")
        }

        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(id: 11, phase: .pressed),
            noErr
        )
        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(id: 11, phase: .released),
            noErr
        )
        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(id: 22, phase: .pressed),
            noErr
        )
        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(id: 22, phase: .released),
            noErr
        )

        XCTAssertEqual(
            events,
            ["press-forward", "release-forward", "press-backward", "release-backward"]
        )
    }

    func testOptionTabHotkeyMonitorPassesThroughUnrelatedEvents() {
        let monitor = OptionTabHotkeyMonitor(signature: 0x54455354, startsMonitoring: false)
        var callbackCount = 0
        monitor.onHotkeyPressed = { _ in callbackCount += 1 }
        monitor.onHotkeyReleased = { _ in callbackCount += 1 }

        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(signature: 0x42414421, id: 1, phase: .pressed),
            OSStatus(eventNotHandledErr)
        )
        XCTAssertEqual(
            monitor.dispatchHotkeyEventForTesting(id: 999, phase: .released),
            OSStatus(eventNotHandledErr)
        )
        XCTAssertEqual(callbackCount, 0)
    }

    func testOptionTabHotkeyMonitorParsesRawCarbonEvents() {
        let monitor = OptionTabHotkeyMonitor(
            signature: 0x54455354,
            forwardHotkeyID: 11,
            backwardHotkeyID: 22,
            startsMonitoring: false
        )

        var events: [String] = []
        monitor.onHotkeyPressed = { isBackward in
            events.append(isBackward ? "press-backward" : "press-forward")
        }
        monitor.onHotkeyReleased = { isBackward in
            events.append(isBackward ? "release-backward" : "release-forward")
        }

        let unsupportedKind = makeCarbonHotkeyEvent(
            kind: UInt32(kEventRawKeyDown),
            signature: 0x54455354,
            id: 11,
            includeHotkeyPayload: true
        )
        XCTAssertEqual(
            monitor.handleHotkeyEventForTesting(unsupportedKind),
            OSStatus(eventNotHandledErr)
        )

        let missingPayload = makeCarbonHotkeyEvent(
            kind: UInt32(kEventHotKeyPressed),
            signature: 0x54455354,
            id: 11,
            includeHotkeyPayload: false
        )
        XCTAssertEqual(
            monitor.handleHotkeyEventForTesting(missingPayload),
            OSStatus(eventNotHandledErr)
        )

        let wrongSignature = makeCarbonHotkeyEvent(
            kind: UInt32(kEventHotKeyPressed),
            signature: 0x42414421,
            id: 11,
            includeHotkeyPayload: true
        )
        XCTAssertEqual(
            monitor.handleHotkeyEventForTesting(wrongSignature),
            OSStatus(eventNotHandledErr)
        )

        let forwardPressed = makeCarbonHotkeyEvent(
            kind: UInt32(kEventHotKeyPressed),
            signature: 0x54455354,
            id: 11,
            includeHotkeyPayload: true
        )
        XCTAssertEqual(monitor.handleHotkeyEventForTesting(forwardPressed), noErr)

        let backwardReleased = makeCarbonHotkeyEvent(
            kind: UInt32(kEventHotKeyReleased),
            signature: 0x54455354,
            id: 22,
            includeHotkeyPayload: true
        )
        XCTAssertEqual(monitor.handleHotkeyEventForTesting(backwardReleased), noErr)

        XCTAssertEqual(events, ["press-forward", "release-backward"])
    }

    func testRuntimeAppLayerProjectionFilterCoversCurrentProcessAndMinimizedApps() {
        XCTAssertFalse(
            RuntimeAppLayerProjectionFilter.shouldIncludeRunningApplication(
                activationPolicy: .accessory,
                isTerminated: false,
                pid: 10,
                currentPID: 99,
                includeCurrentProcessInAppLayer: false
            )
        )
        XCTAssertFalse(
            RuntimeAppLayerProjectionFilter.shouldIncludeRunningApplication(
                activationPolicy: .regular,
                isTerminated: true,
                pid: 10,
                currentPID: 99,
                includeCurrentProcessInAppLayer: false
            )
        )
        XCTAssertFalse(
            RuntimeAppLayerProjectionFilter.shouldIncludeRunningApplication(
                activationPolicy: .regular,
                isTerminated: false,
                pid: 99,
                currentPID: 99,
                includeCurrentProcessInAppLayer: false
            )
        )
        XCTAssertTrue(
            RuntimeAppLayerProjectionFilter.shouldIncludeRunningApplication(
                activationPolicy: .regular,
                isTerminated: false,
                pid: 99,
                currentPID: 99,
                includeCurrentProcessInAppLayer: true
            )
        )

        XCTAssertTrue(
            RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
                hasWindows: false,
                hasVisibleWindow: false,
                hideMinimizedAppsFromAppLayer: true
            )
        )
        XCTAssertFalse(
            RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
                hasWindows: true,
                hasVisibleWindow: false,
                hideMinimizedAppsFromAppLayer: true
            )
        )
        XCTAssertTrue(
            RuntimeAppLayerProjectionFilter.shouldIncludeAppInAppLayer(
                hasWindows: true,
                hasVisibleWindow: true,
                hideMinimizedAppsFromAppLayer: true
            )
        )
    }

    func testSystemAppMRUTrackerRankingPrefersTrackedOrderThenFallbackAndCurrentAppLaunchRank() {
        let rankByPID = SystemAppMRUTracker.rankByPID(
            runningPIDs: [10, 20, 30, 40],
            trackedOrder: [20, 77],
            currentPID: 10,
            launchRankByPID: [10: 5, 20: 0, 30: 2, 40: 1],
            fallbackRankByPID: [30: 0, 40: 1, 10: 2]
        )

        XCTAssertEqual(rankByPID[20], 0)
        XCTAssertEqual(rankByPID[30], 1)
        XCTAssertEqual(rankByPID[40], 2)
        XCTAssertEqual(rankByPID[10], 3)
    }

    func testSystemAppMRUTrackerHelpersCoverNotificationRemovalAndPruningPaths() {
        let tracker = SystemAppMRUTracker.shared
        tracker.resetStateForTesting()
        defer { tracker.resetStateForTesting() }

        tracker.recordActivationForTesting(pid: 4_001)
        tracker.recordActivationForTesting(pid: 4_002)
        tracker.recordActivationForTesting(pid: 4_001)
        XCTAssertEqual(tracker.trackedMRUOrderForTesting(runningPIDs: [4_001, 4_002]), [4_001, 4_002])

        tracker.removeForTesting(pid: 4_002)
        XCTAssertEqual(tracker.trackedMRUOrderForTesting(runningPIDs: [4_001, 4_002]), [4_001])

        tracker.handleApplicationNotificationForTesting(app: nil, removeOnly: true)
        XCTAssertEqual(tracker.trackedMRUOrderForTesting(runningPIDs: [4_001]), [4_001])

        tracker.handleApplicationNotificationForTesting(app: .current, removeOnly: false)
        XCTAssertEqual(
            tracker.trackedMRUOrderForTesting(
                runningPIDs: [4_001, ProcessInfo.processInfo.processIdentifier]
            ),
            [4_001]
        )

        tracker.recordActivationForTesting(pid: 4_999)
        XCTAssertEqual(tracker.trackedMRUOrderForTesting(runningPIDs: [4_001]), [4_001])
    }

    func testSystemAppMRUTrackerRankingFallsBackWhenCurrentPIDLaunchRankIsMissing() {
        let rankByPID = SystemAppMRUTracker.rankByPID(
            runningPIDs: [101, 202],
            trackedOrder: [],
            currentPID: 101,
            launchRankByPID: [:],
            fallbackRankByPID: [202: 0, 101: 5]
        )

        XCTAssertEqual(rankByPID[202], 0)
        XCTAssertEqual(rankByPID[101], 1)
    }

    @MainActor
    func testSystemAppMRUTrackerObserversProcessWorkspaceActivationAndTerminationNotifications() throws {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard
            let otherApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.processIdentifier != currentPID && !$0.isTerminated
            })
        else {
            throw XCTSkip("No secondary running app is available for observer notification coverage.")
        }

        let tracker = SystemAppMRUTracker.shared
        tracker.resetStateForTesting()
        defer { tracker.resetStateForTesting() }

        tracker.startIfNeeded()
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: otherApp]
        )
        XCTAssertEqual(
            tracker.trackedMRUOrderForTesting(runningPIDs: [otherApp.processIdentifier]),
            [otherApp.processIdentifier]
        )

        notificationCenter.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: otherApp]
        )
        XCTAssertEqual(
            tracker.trackedMRUOrderForTesting(runningPIDs: [otherApp.processIdentifier]),
            []
        )
    }

    @MainActor
    func testRuntimeActivatorShortCircuitsActivationForCurrentProcessTarget() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        var observedPID: pid_t?
        var requestActivationCallCount = 0
        activator.activateCurrentAppIfNeededOverride = { app in
            observedPID = app.processIdentifier
            return true
        }
        activator.requestActivationOverride = { _, _ in
            requestActivationCallCount += 1
        }

        activator.activate(
            target: .app(appID: appID),
            contextsByID: [
                appID: makeRuntimeAppContext(appID: appID, runningApp: currentApp, windows: [])
            ]
        )

        XCTAssertEqual(observedPID, currentApp.processIdentifier)
        XCTAssertEqual(requestActivationCallCount, 0)
    }

    @MainActor
    func testRuntimeActivatorWindowActivationRestoresMinimizedWindowAndFallsBackWhenMissing() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }

        var requestedActivationPIDs: [pid_t] = []
        activator.requestActivationOverride = { app, completion in
            requestedActivationPIDs.append(app.processIdentifier)
            completion?(app)
        }

        var focusedWindowCalls: [(id: String, title: String, restore: Bool)] = []
        activator.focusWindowOverride = { windowID, title, restoreIfMinimized, _ in
            focusedWindowCalls.append((windowID, title, restoreIfMinimized))
        }

        let minimizedContext = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: [
                WindowCandidate(id: "mail-1", title: "Inbox", isMinimized: true, lastActiveAt: 10)
            ],
            lastConfirmationSource: .publicExactMatch
        )
        activator.activate(
            target: .window(appID: appID, windowID: "mail-1", restoreIfMinimized: false),
            contextsByID: [appID: minimizedContext]
        )

        XCTAssertEqual(requestedActivationPIDs, [currentApp.processIdentifier])
        XCTAssertEqual(focusedWindowCalls.count, 1)
        XCTAssertEqual(focusedWindowCalls.first?.id, "mail-1")
        XCTAssertEqual(focusedWindowCalls.first?.title, "Inbox")
        XCTAssertEqual(focusedWindowCalls.first?.restore, true)

        requestedActivationPIDs.removeAll()
        focusedWindowCalls.removeAll()

        let missingWindowContext = makeRuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windows: []
        )
        activator.activate(
            target: .window(appID: appID, windowID: "missing", restoreIfMinimized: true),
            contextsByID: [appID: missingWindowContext]
        )

        XCTAssertEqual(requestedActivationPIDs, [currentApp.processIdentifier])
        XCTAssertTrue(focusedWindowCalls.isEmpty)
    }

    @MainActor
    func testRuntimeActivatorIgnoresCachedAXWindowHandlesFromOtherProcesses() {
        let previousAXTrusted = AccessibilityPermissionChecker.isTrustedOverrideForTesting
        defer {
            AccessibilityPermissionChecker.isTrustedOverrideForTesting = previousAXTrusted
        }

        AccessibilityPermissionChecker.isTrustedOverrideForTesting = { false }

        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.requestActivationOverride = { app, completion in
            completion?(app)
        }

        var directFocusOwnerPIDs: [pid_t] = []
        activator.focusAXWindowOverride = { window, _, _ in
            var ownerPID: pid_t = 0
            let ownerResult = AXUIElementGetPid(window, &ownerPID)
            XCTAssertEqual(ownerResult, .success)
            directFocusOwnerPIDs.append(ownerPID)
            return true
        }

        let staleForeignHandle = AXUIElementCreateApplication(currentApp.processIdentifier + 77)
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                "mail-1": RuntimeWindowContext(
                    id: "mail-1",
                    title: "Inbox",
                    isMinimized: false,
                    cgWindowID: nil,
                    inferredTitleBarStyle: nil,
                    axWindow: staleForeignHandle
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: "mail-1", restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertTrue(directFocusOwnerPIDs.isEmpty)
    }

    @MainActor
    func testRuntimeActivatorResolvesCGWindowTargetsBeforeTitleFallback() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.requestActivationOverride = { app, completion in
            completion?(app)
        }

        let liveWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let targetFrame = CGRect(x: 40, y: 60, width: 1440, height: 900)
        let targetCGWindowID: CGWindowID = 243_747
        activator.currentAXWindowsOverride = { _ in
            [liveWindow]
        }
        activator.axWindowTitleOverride = { window in
            CFEqual(window, liveWindow) ? "Fullscreen Target" : nil
        }
        activator.axWindowFrameOverride = { window in
            CFEqual(window, liveWindow) ? targetFrame : nil
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeCGWindowEntry(
                    id: targetCGWindowID,
                    title: "Fullscreen Target",
                    bounds: targetFrame,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        var focusedResolvedWindow = false
        activator.focusAXWindowOverride = { window, restoreIfMinimized, _ in
            XCTAssertFalse(restoreIfMinimized)
            focusedResolvedWindow = CFEqual(window, liveWindow)
            return true
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Fullscreen Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    inferredTitleBarStyle: nil,
                    frame: targetFrame,
                    allowsPublicAXRecovery: true,
                    lastConfirmationSource: .publicExactMatch
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertTrue(focusedResolvedWindow)
    }

    @MainActor
    func testRuntimeActivatorUsesPrivateExactBridgeWhenCGTargetRemainsPubliclyAmbiguous() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.requestActivationOverride = { app, completion in
            completion?(app)
        }

        let targetFrame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let windows = [
            AXUIElementCreateApplication(currentApp.processIdentifier),
            AXUIElementCreateApplication(currentApp.processIdentifier)
        ]
        let targetCGWindowID: CGWindowID = 243_747
        let otherCGWindowID: CGWindowID = 240_029

        activator.currentAXWindowsOverride = { _ in windows }
        activator.axWindowTitleOverride = { _ in "Ambiguous Fullscreen" }
        activator.axWindowFrameOverride = { _ in targetFrame }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeCGWindowEntry(
                    id: targetCGWindowID,
                    title: "Ambiguous Fullscreen",
                    bounds: targetFrame,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1
                ),
                RuntimeCGWindowEntry(
                    id: otherCGWindowID,
                    title: "Ambiguous Fullscreen",
                    bounds: targetFrame,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        let bridgedWindowIDs = Dictionary(
            uniqueKeysWithValues: [
                (Unmanaged.passUnretained(windows[0]).toOpaque(), otherCGWindowID),
                (Unmanaged.passUnretained(windows[1]).toOpaque(), targetCGWindowID)
            ]
        )
        AXWindowInspector.cgWindowIDOverrideForTesting = { window in
            bridgedWindowIDs[Unmanaged.passUnretained(window).toOpaque()]
        }
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }

        var focusedWindowPointer: UnsafeMutableRawPointer?
        activator.focusAXWindowOverride = { window, restoreIfMinimized, _ in
            XCTAssertFalse(restoreIfMinimized)
            focusedWindowPointer = Unmanaged.passUnretained(window).toOpaque()
            return true
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Ambiguous Fullscreen",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    inferredTitleBarStyle: nil,
                    frame: targetFrame,
                    allowsPublicAXRecovery: true,
                    lastConfirmationSource: .privateExactBridge
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(focusedWindowPointer, Unmanaged.passUnretained(windows[1]).toOpaque())
    }

    @MainActor
    func testRuntimeActivatorResolvesFullscreenCGTargetUsingExactTitlesWhenGeometryMatches() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.requestActivationOverride = { app, completion in
            completion?(app)
        }

        let fullscreenFrame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let windows = [
            AXUIElementCreateApplication(currentApp.processIdentifier),
            AXUIElementCreateApplication(currentApp.processIdentifier),
            AXUIElementCreateApplication(currentApp.processIdentifier)
        ]
        let titlesByWindowPointer = Dictionary(
            uniqueKeysWithValues: zip(
                windows.map { Unmanaged.passUnretained($0).toOpaque() },
                [
                    "Google 搜索 - Google Chrome - test1",
                    "Google 搜索 - Google Chrome - test3",
                    "Google 搜索 - Google Chrome - test5"
                ]
            )
        )
        activator.currentAXWindowsOverride = { _ in windows }
        activator.axWindowFrameOverride = { _ in fullscreenFrame }
        activator.axWindowTitleOverride = { window in
            titlesByWindowPointer[Unmanaged.passUnretained(window).toOpaque()]
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeCGWindowEntry(
                    id: 243_679,
                    title: "Google 搜索 - Google Chrome - test3",
                    bounds: fullscreenFrame,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1
                ),
                RuntimeCGWindowEntry(
                    id: 243_747,
                    title: "Google 搜索 - Google Chrome - test1",
                    bounds: fullscreenFrame,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1
                ),
                RuntimeCGWindowEntry(
                    id: 240_029,
                    title: "Google 搜索 - Google Chrome - test5",
                    bounds: fullscreenFrame,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        var focusedWindowPointer: UnsafeMutableRawPointer?
        activator.focusAXWindowOverride = { window, restoreIfMinimized, _ in
            XCTAssertFalse(restoreIfMinimized)
            focusedWindowPointer = Unmanaged.passUnretained(window).toOpaque()
            return true
        }

        let windowID = "cg:\(currentApp.processIdentifier):240029"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Google 搜索 - Google Chrome - test5",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: 240_029,
                    inferredTitleBarStyle: nil,
                    frame: fullscreenFrame,
                    allowsPublicAXRecovery: true,
                    lastConfirmationSource: .publicExactMatch
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(focusedWindowPointer, Unmanaged.passUnretained(windows[2]).toOpaque())
    }

    @MainActor
    func testLiveSwitcherModelHandleApplicationTerminatedRefreshesSessionAndKeepsPreferredNextSelection() async {
        let initialApps = terminateScenarioApps()
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: initialApps)
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )
        XCTAssertEqual(model.selectedApp?.id, "com.example.code")

        let layoutRefreshed = expectation(description: "layout refreshed after app termination")
        model.onSessionLayoutChanged = { layoutRefreshed.fulfill() }

        model.handleApplicationTerminated(appID: "com.example.code", pid: 42_300)

        await fulfillment(of: [layoutRefreshed], timeout: 1.0)
        XCTAssertEqual(runtimeProjectionService.appTerminationSignalsRecorded().map(\.appID), ["com.example.code"])
        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 2
        )
        XCTAssertEqual(model.appCount, 2)
        XCTAssertEqual(model.selectedApp?.id, "com.example.browser")
    }

    @MainActor
    func testLiveSwitcherModelHandleApplicationTerminatedPreservesSearchStateDuringRefresh() async {
        await withTemporarySearchPreferences(enabled: true, defaultScope: .app) {
            let initialApps = self.searchScenarioApps()
            let runtimeProjectionService = RecordingRuntimeProjectionService(
                appSwitcherApps: initialApps
            )
            let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)
            let refreshedApps = initialApps.filter { $0.id != "com.example.code" }

            XCTAssertTrue(model.startSession(triggerDirection: .forward))
            XCTAssertTrue(model.enterSearchMode())
            model.synchronizeSearchInput(query: "bro", cursorPosition: 3)

            let didApplyInitialSearch = await waitUntil(
                "initial search query applies before termination refresh",
                timeoutNanoseconds: 1_000_000_000,
                pollIntervalNanoseconds: 10_000_000
            ) {
                model.isSearchActive
                    && model.searchViewState.query == "bro"
                    && model.searchResultCount >= 1
            }
            XCTAssertTrue(didApplyInitialSearch)
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(model.searchViewState.query, "bro")

            let layoutRefreshed = expectation(description: "layout refreshed while preserving search state")
            model.onSessionLayoutChanged = { layoutRefreshed.fulfill() }
            runtimeProjectionService.installAppSwitcherProjection(apps: refreshedApps)

            model.handleApplicationTerminated(appID: "com.example.code", pid: 42_300)

            await fulfillment(of: [layoutRefreshed], timeout: 1.0)
            let didPreserveSearchAfterRefresh = await waitUntil(
                "termination refresh preserves active search results",
                timeoutNanoseconds: 1_000_000_000,
                pollIntervalNanoseconds: 10_000_000
            ) {
                model.appCount == 2
                    && model.isSearchActive
                    && model.searchViewState.scope == .app
                    && model.searchViewState.query == "bro"
                    && model.searchResultCount >= 1
            }
            XCTAssertTrue(didPreserveSearchAfterRefresh)

            XCTAssertEqual(model.appCount, 2)
            XCTAssertTrue(model.isSearchActive)
            XCTAssertEqual(model.searchViewState.scope, .app)
            XCTAssertEqual(model.searchViewState.query, "bro")
            XCTAssertGreaterThanOrEqual(model.searchResultCount, 1)
        }
    }

    @MainActor
    func testLiveSwitcherModelHandleApplicationTerminatedIgnoresUntrackedApp() {
        let initialApps = terminateScenarioApps()
        let runtimeProjectionService = RecordingRuntimeProjectionService(appSwitcherApps: initialApps)
        let model = LiveSwitcherModel(runtimeProjectionService: runtimeProjectionService)

        XCTAssertTrue(model.startSession(triggerDirection: .forward))
        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )
        let selectedAppID = model.selectedApp?.id

        model.handleApplicationTerminated(appID: "com.example.unrelated", pid: 99_999)

        XCTAssertTrue(runtimeProjectionService.appTerminationSignalsRecorded().isEmpty)
        assertAppSwitcherProjectionRead(
            from: runtimeProjectionService,
            expectedReadCount: 1
        )
        XCTAssertEqual(model.appCount, initialApps.count)
        XCTAssertEqual(model.selectedApp?.id, selectedAppID)
    }

    private func assertAppSwitcherProjectionRead(
        from runtimeProjectionService: RecordingRuntimeProjectionService,
        expectedReadCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherProjectionReadCount(),
            expectedReadCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            runtimeProjectionService.appSwitcherMaintenanceRequestsRecorded(),
            [.switcherSessionStarted],
            file: file,
            line: line
        )
    }

    func testOptionTabHotkeyMonitorSkipsHotkeyRegistrationWhenHandlerInstallFails() {
        var registerCalls: [UInt32] = []
        let monitor = OptionTabHotkeyMonitor(
            signature: 0x54455354,
            forwardHotkeyID: 11,
            backwardHotkeyID: 22,
            startsMonitoring: true,
            handlerInstallerOverride: { false },
            hotkeyRegistrarOverride: { id, _, _ in
                registerCalls.append(id)
                return true
            }
        )

        XCTAssertFalse(monitor.isEventHandlerInstalledForTesting)
        XCTAssertTrue(registerCalls.isEmpty)
    }

    func testOptionTabHotkeyMonitorStopUnregistersOnlySuccessfullyRegisteredHotkeys() {
        var registerCalls: [UInt32] = []
        var unregisterCalls: [UInt32] = []
        var removeHandlerCallCount = 0
        let monitor = OptionTabHotkeyMonitor(
            signature: 0x54455354,
            forwardHotkeyID: 11,
            backwardHotkeyID: 22,
            startsMonitoring: true,
            handlerInstallerOverride: { true },
            hotkeyRegistrarOverride: { id, _, _ in
                registerCalls.append(id)
                return id == 11
            },
            hotkeyUnregisterOverride: { unregisterCalls.append($0) },
            eventHandlerRemoverOverride: { removeHandlerCallCount += 1 }
        )

        XCTAssertTrue(monitor.isEventHandlerInstalledForTesting)
        XCTAssertEqual(registerCalls, [11, 22])

        monitor.stop()

        XCTAssertEqual(unregisterCalls, [11])
        XCTAssertEqual(removeHandlerCallCount, 1)
        XCTAssertFalse(monitor.isEventHandlerInstalledForTesting)
    }

    func testOptionTabHotkeyMonitorRegistrationFailureLogsError() async {
        let defaults = UserDefaults.standard
        let previousVerbose = defaults.object(forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        let previousLevel = defaults.object(forKey: AppPreferenceKeys.runtimeLogLevel)
        defer {
            restoreUserDefaultsValue(
                previousVerbose,
                forKey: AppPreferenceKeys.enableVerboseDiagnostics,
                userDefaults: defaults
            )
            restoreUserDefaultsValue(
                previousLevel,
                forKey: AppPreferenceKeys.runtimeLogLevel,
                userDefaults: defaults
            )
            RuntimeDiagnostics.shared.clear()
        }

        defaults.set(false, forKey: AppPreferenceKeys.enableVerboseDiagnostics)
        defaults.set(RuntimeLogLevel.debug.rawValue, forKey: AppPreferenceKeys.runtimeLogLevel)
        RuntimeDiagnostics.shared.clear()
        _ = await RuntimeDiagnostics.shared.makeReadSnapshot()

        var registerCalls: [UInt32] = []
        let monitor = OptionTabHotkeyMonitor(
            signature: 0x54455354,
            forwardHotkeyID: 11,
            backwardHotkeyID: 22,
            startsMonitoring: true,
            handlerInstallerOverride: { true },
            hotkeyRegistrarOverride: { id, _, _ in
                registerCalls.append(id)
                return false
            }
        )
        defer { monitor.stop() }

        let lines = await RuntimeDiagnostics.shared.readRecentLines(limit: 20, minimumLevel: .error)
        let registerFailureLines = lines.filter {
            $0.contains("[ERROR] [HotKey] register failed signature=1413829460")
        }

        XCTAssertEqual(registerCalls, [11, 22])
        XCTAssertEqual(registerFailureLines.count, 2)
    }

}
