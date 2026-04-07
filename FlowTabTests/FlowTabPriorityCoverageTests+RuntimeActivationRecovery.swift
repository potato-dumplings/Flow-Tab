import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    @MainActor
    func testRuntimeActivatorRetriesWindowRecoveryAfterActivationWhenAXWindowsAppearLate() async {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.requestActivationOverride = { app, completion in
            completion?(app)
        }

        let targetFrame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let targetCGWindowID: CGWindowID = 243_747
        let staleWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let recoveredWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let stalePointer = Unmanaged.passUnretained(staleWindow).toOpaque()
        let recoveredPointer = Unmanaged.passUnretained(recoveredWindow).toOpaque()

        var axWindowReadCount = 0
        activator.currentAXWindowsOverride = { _ in
            axWindowReadCount += 1
            if axWindowReadCount == 1 {
                return []
            }
            return [recoveredWindow]
        }
        activator.axWindowTitleOverride = { window in
            guard Unmanaged.passUnretained(window).toOpaque() == recoveredPointer else { return nil }
            return "Fullscreen Target"
        }
        activator.axWindowFrameOverride = { window in
            guard Unmanaged.passUnretained(window).toOpaque() == recoveredPointer else { return nil }
            return targetFrame
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Fullscreen Target",
                    bounds: targetFrame,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }
        activator.focusRecoveryRetryDelaysNanoseconds = [20_000_000]
        let recoveredFocus = expectation(description: "focus recovered window after activation settles")
        var focusedWindowPointers: [UnsafeMutableRawPointer] = []
        activator.focusAXWindowOverride = { window, restoreIfMinimized, _ in
            XCTAssertFalse(restoreIfMinimized)
            let pointer = Unmanaged.passUnretained(window).toOpaque()
            focusedWindowPointers.append(pointer)
            if pointer == recoveredPointer {
                recoveredFocus.fulfill()
                return true
            }
            if pointer == stalePointer {
                return false
            }
            XCTFail("Unexpected AX window focused")
            return false
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
                    axWindow: staleWindow,
                    frame: targetFrame,
                    allowsPublicAXRecovery: true
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        await fulfillment(of: [recoveredFocus], timeout: 1.0)
        XCTAssertGreaterThanOrEqual(focusedWindowPointers.count, 2)
        XCTAssertEqual(focusedWindowPointers.first, stalePointer)
        XCTAssertEqual(focusedWindowPointers.last, recoveredPointer)
        XCTAssertEqual(axWindowReadCount, 2)
    }
}
