import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab
import FlowTabCore

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testRuntimeActivatorProjectionEventCompletesRecoveryWithoutPollingAction() {
        let scheduler = ManualRuntimeFocusRecoveryScheduler()
        let notificationCenter = NotificationCenter()
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier
            ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator(
            focusRecoveryScheduler: scheduler,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: NotificationCenter()
        )
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryPolicy = RuntimeFocusRecoveryPolicy(
            pollingIntervals: [1],
            watchdogInterval: 10
        )
        activator.focusedAXWindowOverride = { _ in nil }
        activator.currentAXWindowsOverride = { _ in [] }

        let targetCGWindowID: CGWindowID = 245_906
        let targetFrame = CGRect(x: 80, y: 60, width: 900, height: 640)
        var targetIsVisible = false
        var focusedCGWindowIDs: [CGWindowID] = []
        var verifiedCGWindowIDs: [CGWindowID?] = []
        activator.focusCGWindowOverride = { _, cgWindowID in
            focusedCGWindowIDs.append(cgWindowID)
            return true
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeCGWindowEntry(
                    id: targetCGWindowID,
                    title: "Event Target",
                    bounds: targetFrame,
                    isOnscreen: targetIsVisible,
                    alpha: 1,
                    storeType: 1
                )
            ]
        }
        activator.windowFocusVerifiedHandler = {
            verifiedCGWindowIDs.append($0.targetCGWindowID)
        }

        let windowID =
            "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Event Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [2],
                    inferredTitleBarStyle: nil,
                    frame: targetFrame,
                    allowsPublicAXRecovery: true,
                    bindingConfidenceOverride: .inferred,
                    bindingCandidateCount: 1
                )
            ]
        )

        activator.activate(
            target: .window(
                appID: appID,
                windowID: windowID,
                restoreIfMinimized: false
            ),
            contextsByID: [appID: context]
        )
        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID])
        XCTAssertEqual(scheduler.pendingIntervals.sorted(), [1, 10])

        targetIsVisible = true
        notificationCenter.post(
            name: .runtimeCurrentAppWindowProjectionDidUpdate,
            object: self,
            userInfo: [
                RuntimeProjectionNotificationUserInfoKey.appID: appID
            ]
        )

        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID])
        XCTAssertEqual(verifiedCGWindowIDs, [targetCGWindowID])
        XCTAssertTrue(scheduler.pendingIntervals.isEmpty)
    }

    @MainActor
    func testRuntimeActivatorPublishesTheExactAXReadbackThatVerifiedFocus() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier
            ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryPolicy = .disabled

        let targetAXWindow = AXUIElementCreateApplication(
            currentApp.processIdentifier
        )
        let targetCGWindowID: CGWindowID = 245_907
        let previousCGWindowIDOverride =
            AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = { window in
            if CFEqual(window, targetAXWindow) {
                return targetCGWindowID
            }
            return previousCGWindowIDOverride?(window)
        }
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting =
                previousCGWindowIDOverride
        }

        activator.focusCGWindowOverride = { _, _ in false }
        activator.focusAXWindowOverride = { window, _, _ in
            XCTAssertTrue(CFEqual(window, targetAXWindow))
            return true
        }
        var focusedAXReadbackCount = 0
        activator.focusedAXWindowOverride = { _ in
            focusedAXReadbackCount += 1
            return focusedAXReadbackCount == 1 ? targetAXWindow : nil
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeCGWindowEntry(
                    id: targetCGWindowID,
                    title: "Exact Readback Target",
                    bounds: CGRect(x: 80, y: 60, width: 900, height: 640),
                    isOnscreen: true,
                    alpha: 1,
                    storeType: 1,
                    spaceIDs: [2]
                )
            ]
        }

        var verification: RuntimeWindowFocusVerification?
        activator.windowFocusVerifiedHandler = {
            verification = $0
        }

        let windowID =
            "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Exact Readback Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [2],
                    activationHandleID:
                        "ax:\(currentApp.processIdentifier):exact-readback",
                    axWindow: targetAXWindow,
                    frame: CGRect(
                        x: 80,
                        y: 60,
                        width: 900,
                        height: 640
                    ),
                    lastConfirmationSource: .publicExactMatch
                )
            ]
        )

        activator.activate(
            target: .window(
                appID: appID,
                windowID: windowID,
                restoreIfMinimized: false
            ),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(focusedAXReadbackCount, 1)
        XCTAssertEqual(verification?.focusedCGWindowID, targetCGWindowID)
        XCTAssertTrue(
            verification?.focusedAXWindow.map {
                CFEqual($0, targetAXWindow)
            } == true
        )
    }

    @MainActor
    func testRuntimeActivatorPublicAppActivationSkipsWindowBridgeWhenKnownWindowIsOnscreen() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier
            ?? "pid:\(currentApp.processIdentifier)"
        let targetCGWindowID: CGWindowID = 245_908
        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.frontmostApplicationOverride = { currentApp }
        activator.requestActivationOverride = { app, completion in
            completion?(app)
        }
        activator.currentCGWindowsOverride = { _ in
            [self.runtimeActivationWindow(id: targetCGWindowID, isOnscreen: true)]
        }
        var focusedWindowIDs: [String] = []
        activator.focusWindowOverride = { windowID, _, _, _ in
            focusedWindowIDs.append(windowID)
        }

        activator.activate(
            target: .app(
                appID: appID,
                fallback: AppActivationFallback(
                    windowID: windowID,
                    restoreIfMinimized: false
                )
            ),
            contextsByID: [
                appID: runtimeActivationContext(
                    appID: appID,
                    app: currentApp,
                    windowID: windowID,
                    cgWindowID: targetCGWindowID
                )
            ]
        )

        XCTAssertTrue(focusedWindowIDs.isEmpty)
    }

    @MainActor
    func testRuntimeActivatorPublicAppActivationUsesFallbackWhenNoKnownWindowIsOnscreen() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier
            ?? "pid:\(currentApp.processIdentifier)"
        let targetCGWindowID: CGWindowID = 245_909
        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.frontmostApplicationOverride = { currentApp }
        activator.requestActivationOverride = { app, completion in
            completion?(app)
        }
        activator.currentCGWindowsOverride = { _ in
            [self.runtimeActivationWindow(id: targetCGWindowID, isOnscreen: false)]
        }
        activator.focusRecoveryPolicy = .disabled
        var focusedWindowIDs: [String] = []
        activator.focusWindowOverride = { windowID, _, _, _ in
            focusedWindowIDs.append(windowID)
        }

        activator.activate(
            target: .app(
                appID: appID,
                fallback: AppActivationFallback(
                    windowID: windowID,
                    restoreIfMinimized: false
                )
            ),
            contextsByID: [
                appID: runtimeActivationContext(
                    appID: appID,
                    app: currentApp,
                    windowID: windowID,
                    cgWindowID: targetCGWindowID
                )
            ]
        )

        XCTAssertEqual(focusedWindowIDs, [windowID])
    }

    @MainActor
    func testRuntimeActivatorIgnoresStalePublicAppActivationCompletion() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier
            ?? "pid:\(currentApp.processIdentifier)"
        let targetCGWindowID: CGWindowID = 245_910
        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.frontmostApplicationOverride = { currentApp }
        var completions: [(NSRunningApplication) -> Void] = []
        activator.requestActivationOverride = { _, completion in
            if let completion {
                completions.append(completion)
            }
        }
        activator.currentCGWindowsOverride = { _ in [] }
        var focusedWindowIDs: [String] = []
        activator.focusWindowOverride = { windowID, _, _, _ in
            focusedWindowIDs.append(windowID)
        }
        let context = runtimeActivationContext(
            appID: appID,
            app: currentApp,
            windowID: windowID,
            cgWindowID: targetCGWindowID
        )

        activator.activate(
            target: .app(
                appID: appID,
                fallback: AppActivationFallback(
                    windowID: windowID,
                    restoreIfMinimized: false
                )
            ),
            contextsByID: [appID: context]
        )
        activator.activate(
            target: .app(appID: appID),
            contextsByID: [appID: context]
        )
        completions.first?(currentApp)

        XCTAssertEqual(completions.count, 1)
        XCTAssertTrue(focusedWindowIDs.isEmpty)
    }

    @MainActor
    func testRuntimeActivatorSkipsFallbackWhenApplicationTerminatesBeforeCompletion() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier
            ?? "pid:\(currentApp.processIdentifier)"
        let targetCGWindowID: CGWindowID = 245_911
        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        var completion: ((NSRunningApplication) -> Void)?
        activator.requestActivationOverride = { _, callback in
            completion = callback
        }
        activator.applicationIsTerminatedOverride = { _ in true }
        var focusedWindowIDs: [String] = []
        activator.focusWindowOverride = { windowID, _, _, _ in
            focusedWindowIDs.append(windowID)
        }

        activator.activate(
            target: .app(
                appID: appID,
                fallback: AppActivationFallback(
                    windowID: windowID,
                    restoreIfMinimized: false
                )
            ),
            contextsByID: [
                appID: runtimeActivationContext(
                    appID: appID,
                    app: currentApp,
                    windowID: windowID,
                    cgWindowID: targetCGWindowID
                )
            ]
        )
        completion?(currentApp)

        XCTAssertTrue(focusedWindowIDs.isEmpty)
    }

    @MainActor
    func testRuntimeActivatorSkipsMissingAppFallbackWindowContext() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier
            ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.frontmostApplicationOverride = { currentApp }
        activator.requestActivationOverride = { app, completion in
            completion?(app)
        }
        activator.currentCGWindowsOverride = { _ in [] }
        var focusedWindowIDs: [String] = []
        activator.focusWindowOverride = { windowID, _, _, _ in
            focusedWindowIDs.append(windowID)
        }

        activator.activate(
            target: .app(
                appID: appID,
                fallback: AppActivationFallback(
                    windowID: "missing-window",
                    restoreIfMinimized: false
                )
            ),
            contextsByID: [
                appID: RuntimeAppContext(
                    appID: appID,
                    runningApp: currentApp,
                    windowsByID: [:]
                )
            ]
        )

        XCTAssertTrue(focusedWindowIDs.isEmpty)
    }

    func testExactWindowFocusStateVerificationMatrix() {
        let targetCGWindowID: CGWindowID = 245_912
        let otherCGWindowID: CGWindowID = 245_913
        let visibleTarget = runtimeActivationWindow(
            id: targetCGWindowID,
            isOnscreen: true
        )
        let offscreenTarget = runtimeActivationWindow(
            id: targetCGWindowID,
            isOnscreen: false
        )
        let visibleOther = runtimeActivationWindow(
            id: otherCGWindowID,
            isOnscreen: true
        )

        XCTAssertTrue(
            RuntimeExactWindowFocusState(
                targetCGWindowID: targetCGWindowID,
                currentWindows: [visibleTarget, visibleOther],
                focusReadback: RuntimeWindowFocusReadbackEvidence(
                    focusedAXWindow: nil,
                    focusedCGWindowID: targetCGWindowID
                )
            ).isVerified
        )
        XCTAssertTrue(
            RuntimeExactWindowFocusState(
                targetCGWindowID: targetCGWindowID,
                currentWindows: [visibleTarget, visibleOther],
                focusReadback: RuntimeWindowFocusReadbackEvidence(
                    focusedAXWindow: nil,
                    focusedCGWindowID: nil
                )
            ).isVerified
        )
        XCTAssertFalse(
            RuntimeExactWindowFocusState(
                targetCGWindowID: targetCGWindowID,
                currentWindows: [visibleOther, offscreenTarget],
                focusReadback: RuntimeWindowFocusReadbackEvidence(
                    focusedAXWindow: nil,
                    focusedCGWindowID: targetCGWindowID
                )
            ).isVerified
        )
        XCTAssertFalse(
            RuntimeExactWindowFocusState(
                targetCGWindowID: targetCGWindowID,
                currentWindows: [visibleTarget, visibleOther],
                focusReadback: RuntimeWindowFocusReadbackEvidence(
                    focusedAXWindow: nil,
                    focusedCGWindowID: otherCGWindowID
                )
            ).isVerified
        )
    }

    @MainActor
    private func runtimeActivationContext(
        appID: String,
        app: NSRunningApplication,
        windowID: String,
        cgWindowID: CGWindowID
    ) -> RuntimeAppContext {
        RuntimeAppContext(
            appID: appID,
            runningApp: app,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Activation Target",
                    isMinimized: false,
                    ownerPID: app.processIdentifier,
                    cgWindowID: cgWindowID,
                    spaceIDs: [2],
                    frame: CGRect(x: 80, y: 60, width: 900, height: 640),
                    lastConfirmationSource: .publicExactMatch
                )
            ]
        )
    }

    private func runtimeActivationWindow(
        id: CGWindowID,
        isOnscreen: Bool
    ) -> RuntimeCGWindowEntry {
        RuntimeCGWindowEntry(
            id: id,
            title: "Activation Target",
            bounds: CGRect(x: 80, y: 60, width: 900, height: 640),
            isOnscreen: isOnscreen,
            alpha: 1,
            storeType: 1,
            spaceIDs: [2]
        )
    }
}
