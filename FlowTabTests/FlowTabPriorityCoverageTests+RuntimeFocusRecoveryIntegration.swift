import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab

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
                    isOnscreen: false,
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
}
