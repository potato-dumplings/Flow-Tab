import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testChromeFocusBridgeScriptUsesNamedPropagationDelay() {
        let script = RuntimeChromeWindowFocusBridge.focusWindowScriptForTesting(windowID: 12_345)

        XCTAssertEqual(
            RuntimeChromeWindowFocusBridge.scriptStatePropagationDelaySecondsForTesting,
            0.05
        )
        XCTAssertTrue(script.contains("set targetWindowID to 12345"))
        XCTAssertEqual(script.components(separatedBy: "delay 0.05").count - 1, 2)
        XCTAssertFalse(script.contains("delay 0.050"))
    }

    func testChromeFocusBridgeUsesScriptableBrowserSpecForScripts() {
        let chromeSpec = RuntimeChromeWindowFocusBridge.scriptableBrowserSpec(
            forBundleIdentifier: "com.google.Chrome"
        )

        XCTAssertEqual(chromeSpec, .chrome)
        XCTAssertNil(
            RuntimeChromeWindowFocusBridge.scriptableBrowserSpec(
                forBundleIdentifier: "com.example.unsupported-browser"
            )
        )
        XCTAssertTrue(
            RuntimeChromeWindowFocusBridge.focusWindowScriptForTesting(
                windowID: 12_345,
                bundleIdentifier: "com.google.Chrome"
            )?.contains("tell application id \"com.google.Chrome\"") ?? false
        )
        XCTAssertTrue(
            RuntimeChromeWindowFocusBridge.windowListScriptForTesting(
                bundleIdentifier: "com.google.Chrome"
            )?.contains("tell application id \"com.google.Chrome\"") ?? false
        )
        XCTAssertNil(
            RuntimeChromeWindowFocusBridge.focusWindowScriptForTesting(
                windowID: 12_345,
                bundleIdentifier: "com.example.unsupported-browser"
            )
        )
    }

    func testChromeFocusBridgeCandidateDecisionRejectsCloseCandidates() {
        let frame = CGRect(x: 0, y: 40, width: 1_200, height: 800)
        let candidates = [
            RuntimeChromeWindowFocusBridge.Candidate(
                windowID: 31,
                name: "Inbox - Gmail",
                activeTabTitle: "Inbox - Gmail",
                bounds: frame,
                titleAffinity: 0,
                geometryDistance: 12
            ),
            RuntimeChromeWindowFocusBridge.Candidate(
                windowID: 44,
                name: "Inbox - Gmail",
                activeTabTitle: "Inbox - Gmail",
                bounds: frame.offsetBy(dx: 3, dy: 0),
                titleAffinity: 0,
                geometryDistance: 15
            )
        ]

        let decision = RuntimeChromeWindowFocusBridge.candidateDecision(
            candidates,
            targetCGWindowID: 456,
            fallbackTitle: "Inbox - Gmail",
            fallbackFrame: frame,
            currentCGWindows: []
        )

        guard case let .ambiguous(ambiguousCandidates, reason) = decision else {
            return XCTFail("Expected close Chrome candidates to remain ambiguous")
        }
        XCTAssertEqual(reason, "insufficient-score-separation")
        XCTAssertEqual(ambiguousCandidates.map(\.windowID), [31, 44])
        XCTAssertNil(
            RuntimeChromeWindowFocusBridge.selectCandidate(
                candidates,
                targetCGWindowID: 456,
                fallbackTitle: "Inbox - Gmail",
                fallbackFrame: frame,
                currentCGWindows: []
            )
        )
    }

    func testChromeFocusBridgeCandidateDecisionSelectsClearCandidate() {
        let frame = CGRect(x: 0, y: 40, width: 1_200, height: 800)
        let clearCandidate = RuntimeChromeWindowFocusBridge.Candidate(
            windowID: 31,
            name: "Inbox - Gmail",
            activeTabTitle: "Inbox - Gmail",
            bounds: frame,
            titleAffinity: 0,
            geometryDistance: 12
        )
        let weakCandidate = RuntimeChromeWindowFocusBridge.Candidate(
            windowID: 44,
            name: "Calendar",
            activeTabTitle: "Calendar",
            bounds: frame.offsetBy(dx: 320, dy: 0),
            titleAffinity: 2,
            geometryDistance: 320
        )

        let decision = RuntimeChromeWindowFocusBridge.candidateDecision(
            [clearCandidate, weakCandidate],
            targetCGWindowID: 456,
            fallbackTitle: "Inbox - Gmail",
            fallbackFrame: frame,
            currentCGWindows: []
        )

        guard case let .selected(candidate, confidence) = decision else {
            return XCTFail("Expected clear Chrome candidate to be selected")
        }
        XCTAssertEqual(candidate.windowID, 31)
        XCTAssertEqual(confidence, .uniqueStrongSignals)
    }

    func testChromeFocusBridgeCandidateDecisionReportsQueryErrorAsUnavailable() {
        let query = RuntimeChromeWindowFocusBridge.CandidateQuery(
            candidates: [],
            chromeWindowCount: 0,
            error: "apple-event-not-authorized"
        )

        let decision = RuntimeChromeWindowFocusBridge.candidateDecision(
            query,
            targetCGWindowID: 456,
            fallbackTitle: "Inbox - Gmail",
            fallbackFrame: CGRect(x: 0, y: 40, width: 1_200, height: 800),
            currentCGWindows: []
        )

        guard case let .unavailable(reason) = decision else {
            return XCTFail("Expected Chrome candidate query error to become unavailable decision")
        }
        XCTAssertEqual(reason, "candidate-query-error:apple-event-not-authorized")
        XCTAssertTrue(decision.logDescription.contains("unavailable:reason="))
        XCTAssertTrue(decision.logDescription.contains("apple-event-not-authorized"))
    }

    func testChromeFocusBridgeCandidateDecisionUsesTargetOrdinalForScoreTies() {
        let frame = CGRect(x: 0, y: 40, width: 1_200, height: 800)
        let candidates = [
            RuntimeChromeWindowFocusBridge.Candidate(
                windowID: 31,
                name: "Inbox - Gmail",
                activeTabTitle: "Inbox - Gmail",
                bounds: frame,
                titleAffinity: 0,
                geometryDistance: 12
            ),
            RuntimeChromeWindowFocusBridge.Candidate(
                windowID: 44,
                name: "Inbox - Gmail",
                activeTabTitle: "Inbox - Gmail",
                bounds: frame,
                titleAffinity: 0,
                geometryDistance: 12
            )
        ]
        let cgWindows = [
            RuntimeSnapshotProvider.CGWindowEntry(
                id: 455,
                title: "Inbox - Gmail",
                bounds: frame,
                isOnscreen: false,
                alpha: 1,
                storeType: 1
            ),
            RuntimeSnapshotProvider.CGWindowEntry(
                id: 456,
                title: "Inbox - Gmail",
                bounds: frame,
                isOnscreen: false,
                alpha: 1,
                storeType: 1
            )
        ]

        let decision = RuntimeChromeWindowFocusBridge.candidateDecision(
            candidates,
            targetCGWindowID: 456,
            fallbackTitle: "Inbox - Gmail",
            fallbackFrame: frame,
            currentCGWindows: cgWindows
        )

        guard case let .selected(candidate, confidence) = decision else {
            return XCTFail("Expected target ordinal to resolve the score tie")
        }
        XCTAssertEqual(candidate.windowID, 44)
        XCTAssertEqual(confidence, .targetOrdinalTieBreak)
    }

    func testChromeFocusBridgeCandidateDecisionUsesTargetOrdinalWhenCGTitlesAreUnavailable() {
        let frame = CGRect(x: 0, y: 40, width: 1_200, height: 800)
        let candidates = [
            RuntimeChromeWindowFocusBridge.Candidate(
                windowID: 31,
                name: "First Tab",
                activeTabTitle: "First Tab",
                bounds: frame,
                titleAffinity: 2,
                geometryDistance: 12
            ),
            RuntimeChromeWindowFocusBridge.Candidate(
                windowID: 44,
                name: "Second Tab",
                activeTabTitle: "Second Tab",
                bounds: frame,
                titleAffinity: 2,
                geometryDistance: 12
            )
        ]
        let cgWindows = [
            RuntimeSnapshotProvider.CGWindowEntry(
                id: 455,
                title: nil,
                bounds: frame,
                isOnscreen: false,
                alpha: 1,
                storeType: 1
            ),
            RuntimeSnapshotProvider.CGWindowEntry(
                id: 456,
                title: nil,
                bounds: frame,
                isOnscreen: false,
                alpha: 1,
                storeType: 1
            )
        ]

        let decision = RuntimeChromeWindowFocusBridge.candidateDecision(
            candidates,
            targetCGWindowID: 456,
            fallbackTitle: "Google Chrome",
            fallbackFrame: frame,
            currentCGWindows: cgWindows
        )

        guard case let .selected(candidate, confidence) = decision else {
            return XCTFail("Expected target ordinal to resolve the title-unavailable score tie")
        }
        XCTAssertEqual(candidate.windowID, 44)
        XCTAssertEqual(confidence, .targetOrdinalTieBreak)
    }

    @MainActor
    func testRuntimeActivatorActivationConfirmationPolicyWrapsRetryDelays() {
        let activator = RuntimeActivator()

        XCTAssertEqual(
            activator.activationConfirmationPolicy,
            .defaultFocusRecovery
        )
        XCTAssertTrue(activator.activationConfirmationPolicy.isEnabled)

        activator.focusRecoveryRetryDelaysNanoseconds = [1, 2, 3]
        XCTAssertEqual(
            activator.activationConfirmationPolicy,
            ActivationConfirmationPolicy(retryDelaysNanoseconds: [1, 2, 3])
        )

        activator.activationConfirmationPolicy = ActivationConfirmationPolicy(
            retryDelaysNanoseconds: []
        )
        XCTAssertTrue(activator.focusRecoveryRetryDelaysNanoseconds.isEmpty)
        XCTAssertFalse(activator.activationConfirmationPolicy.isEnabled)
    }

    func testRuntimeCGWindowFocusBridgeClassifiesStructuredResults() {
        XCTAssertTrue(RuntimeCGWindowFocusBridge.FocusResult.accepted.isAccepted)
        XCTAssertTrue(RuntimeCGWindowFocusBridge.FocusResult.acceptedKeyEventFailed.isAccepted)
        XCTAssertFalse(RuntimeCGWindowFocusBridge.FocusResult.symbolUnavailable.isAccepted)
        XCTAssertFalse(RuntimeCGWindowFocusBridge.FocusResult.processLookupFailed(-600).isAccepted)
        XCTAssertFalse(RuntimeCGWindowFocusBridge.FocusResult.setFrontFailed(1000).isAccepted)

        XCTAssertEqual(
            RuntimeCGWindowFocusBridge.FocusResult.acceptedKeyEventFailed.debugName,
            "acceptedKeyEventFailed"
        )
        XCTAssertEqual(
            RuntimeCGWindowFocusBridge.FocusResult.processLookupFailed(-600).debugName,
            "processLookupFailed(-600)"
        )
        XCTAssertEqual(
            RuntimeCGWindowFocusBridge.FocusResult.setFrontFailed(1000).debugName,
            "setFrontFailed(1000)"
        )
    }

    @MainActor
    func testRuntimeActivatorRetriesWhenAXFocusLeavesSpaceTargetOffscreen() async {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.requestActivationOverride = { app, completion in
            completion?(app)
        }

        let targetFrame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let targetCGWindowID: CGWindowID = 245_101
        let axWindow = AXUIElementCreateApplication(currentApp.processIdentifier)

        activator.focusRecoveryRetryDelaysNanoseconds = [20_000_000]
        var focusCallCount = 0
        activator.focusAXWindowOverride = { window, restoreIfMinimized, _ in
            XCTAssertTrue(CFEqual(window, axWindow))
            XCTAssertFalse(restoreIfMinimized)
            focusCallCount += 1
            return true
        }

        let verifiedVisibleTarget = expectation(description: "focus retry verifies target CG window onscreen")
        var didFulfillVisibleTarget = false
        var visibilityChecks: [Bool] = []
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            let isVisible = focusCallCount >= 2
            visibilityChecks.append(isVisible)
            if isVisible, !didFulfillVisibleTarget {
                didFulfillVisibleTarget = true
                verifiedVisibleTarget.fulfill()
            }
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Fullscreen Target",
                    bounds: targetFrame,
                    isOnscreen: isVisible,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
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
                    spaceIDs: [2],
                    inferredTitleBarStyle: nil,
                    axWindow: axWindow,
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

        await fulfillment(of: [verifiedVisibleTarget], timeout: 1.0)
        XCTAssertEqual(focusCallCount, 2)
        XCTAssertEqual(visibilityChecks.first, false)
        XCTAssertTrue(visibilityChecks.contains(true))
    }

    @MainActor
    func testRuntimeActivatorSkipsPublicActivationForCGOnlyOffscreenSpaceTargetWithoutRoute() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        var requestActivationCallCount = 0
        activator.requestActivationOverride = { _, completion in
            requestActivationCallCount += 1
            completion?(currentApp)
        }
        activator.focusAXWindowOverride = { _, _, _ in
            XCTFail("CG-only no-route activation should not synthesize an AX focus")
            return true
        }
        activator.currentAXWindowsOverride = { _ in
            XCTFail("CG-only no-route activation should not search AX windows without recovery permission")
            return []
        }

        let targetFrame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let targetCGWindowID: CGWindowID = 245_202
        var cgWindowReadCount = 0
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            cgWindowReadCount += 1
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "CG Only Target",
                    bounds: targetFrame,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "CG Only Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [2],
                    inferredTitleBarStyle: nil,
                    frame: targetFrame,
                    allowsPublicAXRecovery: false
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(requestActivationCallCount, 0)
        XCTAssertEqual(cgWindowReadCount, 0)
    }

    @MainActor
    func testRuntimeActivatorSkipsActivationWhenBindingDisallowsActivationActions() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = [20_000_000]

        var requestActivationCallCount = 0
        activator.requestActivationOverride = { _, completion in
            requestActivationCallCount += 1
            completion?(currentApp)
        }
        activator.focusCGWindowOverride = { _, _ in
            XCTFail("Ambiguous binding must not use CG activation fallback")
            return true
        }
        activator.focusAXWindowOverride = { _, _, _ in
            XCTFail("Ambiguous binding must not use AX activation")
            return true
        }
        activator.currentAXWindowsOverride = { _ in
            XCTFail("Ambiguous binding must not enter AX recovery")
            return []
        }
        activator.currentCGWindowsOverride = { _ in
            XCTFail("Ambiguous binding must not read CG focus state")
            return []
        }

        let targetCGWindowID: CGWindowID = 245_250
        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Ambiguous Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    axWindow: AXUIElementCreateApplication(currentApp.processIdentifier),
                    allowsPublicAXRecovery: true,
                    bindingConfidenceOverride: .ambiguous,
                    bindingCandidateCount: 2
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(requestActivationCallCount, 0)
    }

    @MainActor
    func testRuntimeActivatorUsesCGFallbackButSkipsDirectAXForInferredBinding() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        let axWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        activator.focusAXWindowOverride = { _, _, _ in
            XCTFail("Inferred binding must not reuse stored direct AX handle")
            return true
        }

        let targetCGWindowID: CGWindowID = 245_251
        var focusedCGWindowIDs: [CGWindowID] = []
        activator.focusCGWindowOverride = { app, cgWindowID in
            XCTAssertEqual(app.processIdentifier, currentApp.processIdentifier)
            focusedCGWindowIDs.append(cgWindowID)
            return true
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Inferred Target",
                    bounds: CGRect(x: 0, y: 40, width: 960, height: 640),
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Inferred Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    activationHandleID: "ax:\(currentApp.processIdentifier):inferred",
                    axWindow: axWindow,
                    allowsPublicAXRecovery: true,
                    bindingConfidenceOverride: .inferred,
                    bindingCandidateCount: 1
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID])
    }

    @MainActor
    func testRuntimeActivatorAllowsDirectAXFallbackForStickyBindingWithExactCGReadback() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        let targetAXWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let targetPointer = Unmanaged.passUnretained(targetAXWindow).toOpaque()
        let targetCGWindowID: CGWindowID = 245_254
        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = { window in
            let pointer = Unmanaged.passUnretained(window).toOpaque()
            return pointer == targetPointer ? targetCGWindowID : previousExactBridgeOverride?(window)
        }
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }

        var focusedCGWindowIDs: [CGWindowID] = []
        activator.focusCGWindowOverride = { app, cgWindowID in
            XCTAssertEqual(app.processIdentifier, currentApp.processIdentifier)
            focusedCGWindowIDs.append(cgWindowID)
            return true
        }

        var focusedAXWindowPointers: [UnsafeMutableRawPointer] = []
        activator.focusAXWindowOverride = { window, restoreIfMinimized, _ in
            XCTAssertFalse(restoreIfMinimized)
            focusedAXWindowPointers.append(Unmanaged.passUnretained(window).toOpaque())
            return true
        }
        activator.focusedAXWindowOverride = { _ in targetAXWindow }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Sticky Target",
                    bounds: CGRect(x: 0, y: 40, width: 960, height: 640),
                    isOnscreen: !focusedAXWindowPointers.isEmpty,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [1]
                )
            ]
        }

        var verifiedAllowedActions: [Set<WindowBindingAction>] = []
        activator.windowFocusVerifiedHandler = { _, _, _, _, _, _, allowedActions in
            verifiedAllowedActions.append(allowedActions)
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Sticky Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [1],
                    activationHandleID: "ax:\(currentApp.processIdentifier):sticky-target",
                    axWindow: targetAXWindow,
                    allowsPublicAXRecovery: false,
                    hasStickyBinding: true,
                    lastConfirmationSource: .stickyBinding
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID])
        XCTAssertEqual(focusedAXWindowPointers, [targetPointer])
        XCTAssertEqual(verifiedAllowedActions.count, 1)
        XCTAssertFalse(verifiedAllowedActions[0].contains(.useForAXActivation))
        XCTAssertFalse(verifiedAllowedActions[0].contains(.updateRecency))
    }

    @MainActor
    func testRuntimeActivatorRejectsDirectAXFallbackForStickyBindingWithMismatchedCGReadback() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        let staleAXWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let stalePointer = Unmanaged.passUnretained(staleAXWindow).toOpaque()
        let targetCGWindowID: CGWindowID = 245_255
        let staleCGWindowID: CGWindowID = 245_256
        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = { window in
            let pointer = Unmanaged.passUnretained(window).toOpaque()
            return pointer == stalePointer ? staleCGWindowID : previousExactBridgeOverride?(window)
        }
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }

        var focusedCGWindowIDs: [CGWindowID] = []
        activator.focusCGWindowOverride = { app, cgWindowID in
            XCTAssertEqual(app.processIdentifier, currentApp.processIdentifier)
            focusedCGWindowIDs.append(cgWindowID)
            return true
        }
        activator.focusAXWindowOverride = { _, _, _ in
            XCTFail("Sticky AX fallback must not focus a handle that bridges to another CG window")
            return true
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Sticky Target",
                    bounds: CGRect(x: 0, y: 40, width: 960, height: 640),
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [1]
                )
            ]
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Sticky Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [1],
                    activationHandleID: "ax:\(currentApp.processIdentifier):stale-sticky-target",
                    axWindow: staleAXWindow,
                    allowsPublicAXRecovery: false,
                    hasStickyBinding: true,
                    lastConfirmationSource: .stickyBinding
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID])
    }

    @MainActor
    func testRuntimeActivatorReportsBindingReadbackMismatchWhenFocusCannotVerifyTargetCG() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        let axWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        activator.focusCGWindowOverride = { _, _ in false }
        activator.focusAXWindowOverride = { window, _, _ in
            XCTAssertTrue(CFEqual(window, axWindow))
            return true
        }

        let targetCGWindowID: CGWindowID = 245_252
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Readback Target",
                    bounds: CGRect(x: 0, y: 40, width: 960, height: 640),
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1
                ),
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: 245_253,
                    title: "Visible Other",
                    bounds: CGRect(x: 40, y: 80, width: 800, height: 600),
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        var verifiedFocuses: [CGWindowID?] = []
        activator.windowFocusVerifiedHandler = { _, _, _, cgWindowID, _, _, _ in
            verifiedFocuses.append(cgWindowID)
        }
        var mismatchDiagnostics: [WindowBindingReadbackDiagnostic] = []
        activator.windowFocusReadbackMismatchHandler = {
            mismatchDiagnostics.append($0)
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Readback Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [1],
                    activationHandleID: "ax:\(currentApp.processIdentifier):readback",
                    axWindow: axWindow,
                    lastConfirmationSource: .publicExactMatch
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertTrue(verifiedFocuses.isEmpty)
        XCTAssertEqual(mismatchDiagnostics.count, 1)
        XCTAssertEqual(mismatchDiagnostics.first?.appID, appID)
        XCTAssertEqual(mismatchDiagnostics.first?.windowID, windowID)
        XCTAssertEqual(mismatchDiagnostics.first?.route, "ax-direct")
        XCTAssertEqual(mismatchDiagnostics.first?.reason, .targetCGNotVisible)
        XCTAssertEqual(mismatchDiagnostics.first?.targetCGWindowID, targetCGWindowID)
        XCTAssertEqual(mismatchDiagnostics.first?.visibleCGWindowIDs, [245_253])
        XCTAssertEqual(mismatchDiagnostics.first?.bindingConfidence, .exact)
        XCTAssertTrue(
            mismatchDiagnostics.first?.allowedActions.contains(.updateStickyHistory) == true
        )
    }

    @MainActor
    func testRuntimeActivatorReportsFocusedAXCGWindowMismatchWhenVisibleTargetIsNotFocused() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        let targetAXWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let focusedAXWindow = AXUIElementCreateApplication(currentApp.processIdentifier + 1)
        let targetCGWindowID: CGWindowID = 245_262
        let focusedCGWindowID: CGWindowID = 245_263
        let previousCGWindowIDOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = { window in
            if CFEqual(window, targetAXWindow) {
                return targetCGWindowID
            }
            if CFEqual(window, focusedAXWindow) {
                return focusedCGWindowID
            }
            return previousCGWindowIDOverride?(window)
        }
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousCGWindowIDOverride
        }

        activator.focusCGWindowOverride = { _, _ in false }
        activator.focusAXWindowOverride = { window, _, _ in
            XCTAssertTrue(CFEqual(window, targetAXWindow))
            return true
        }
        activator.focusedAXWindowOverride = { _ in focusedAXWindow }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Visible Target",
                    bounds: CGRect(x: 0, y: 40, width: 960, height: 640),
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [1]
                ),
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: focusedCGWindowID,
                    title: "Focused Other",
                    bounds: CGRect(x: 40, y: 80, width: 800, height: 600),
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [1]
                )
            ]
        }

        var verifiedFocuses: [CGWindowID?] = []
        activator.windowFocusVerifiedHandler = { _, _, _, cgWindowID, _, _, _ in
            verifiedFocuses.append(cgWindowID)
        }
        var mismatchDiagnostics: [WindowBindingReadbackDiagnostic] = []
        activator.windowFocusReadbackMismatchHandler = {
            mismatchDiagnostics.append($0)
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Visible Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [1],
                    activationHandleID: "ax:\(currentApp.processIdentifier):focused-mismatch",
                    axWindow: targetAXWindow,
                    allowsPublicAXRecovery: false,
                    lastConfirmationSource: .publicExactMatch
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertTrue(verifiedFocuses.isEmpty)
        XCTAssertEqual(mismatchDiagnostics.count, 1)
        XCTAssertEqual(mismatchDiagnostics.first?.route, "ax-direct")
        XCTAssertEqual(mismatchDiagnostics.first?.reason, .focusedAXCGWindowMismatch)
        XCTAssertEqual(mismatchDiagnostics.first?.targetCGWindowID, targetCGWindowID)
        XCTAssertEqual(mismatchDiagnostics.first?.focusedCGWindowID, focusedCGWindowID)
        XCTAssertEqual(mismatchDiagnostics.first?.visibleCGWindowIDs, [targetCGWindowID, focusedCGWindowID])
    }

    @MainActor
    func testRuntimeActivatorFocusesCGOnlySpaceTargetThroughCGWindowBridge() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        var requestActivationCallCount = 0
        activator.requestActivationOverride = { _, completion in
            requestActivationCallCount += 1
            completion?(currentApp)
        }
        activator.currentAXWindowsOverride = { _ in
            XCTFail("CG-only bridge activation should not need public AX window recovery")
            return []
        }
        activator.focusAXWindowOverride = { _, _, _ in
            XCTFail("CG-only bridge activation should not synthesize an AX focus")
            return true
        }

        let targetFrame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let targetCGWindowID: CGWindowID = 245_303
        var focusedCGWindowIDs: [CGWindowID] = []
        activator.focusCGWindowOverride = { app, cgWindowID in
            XCTAssertEqual(app.processIdentifier, currentApp.processIdentifier)
            focusedCGWindowIDs.append(cgWindowID)
            return true
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "CG Bridge Target",
                    bounds: targetFrame,
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "CG Bridge Target",
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
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(requestActivationCallCount, 0)
        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID])
    }

    @MainActor
    func testRuntimeActivatorDoesNotFocusPublicAXWindowByTitleOnlyForDifferentCGTarget() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        let sameTitleAXWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let sameTitlePointer = Unmanaged.passUnretained(sameTitleAXWindow).toOpaque()
        let targetFrame = CGRect(x: 0, y: 158, width: 1_728, height: 959)
        let sameTitleFrame = CGRect(x: 384, y: 258, width: 960, height: 640)
        let targetCGWindowID: CGWindowID = 245_607
        let sameTitleCGWindowID: CGWindowID = 245_608

        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = { window in
            let pointer = Unmanaged.passUnretained(window).toOpaque()
            return pointer == sameTitlePointer ? sameTitleCGWindowID : nil
        }
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }

        activator.currentAXWindowsOverride = { _ in [sameTitleAXWindow] }
        activator.axWindowTitleOverride = { _ in "New Tab" }
        activator.axWindowFrameOverride = { _ in sameTitleFrame }
        activator.focusAXWindowOverride = { _, _, _ in
            XCTFail("Title-only AX recovery must not focus a different CG window")
            return true
        }

        var focusedCGWindowIDs: [CGWindowID] = []
        activator.focusCGWindowOverride = { app, cgWindowID in
            XCTAssertEqual(app.processIdentifier, currentApp.processIdentifier)
            focusedCGWindowIDs.append(cgWindowID)
            return true
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: sameTitleCGWindowID,
                    title: "New Tab",
                    bounds: sameTitleFrame,
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [1]
                ),
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "New Tab",
                    bounds: targetFrame,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [8_912]
                )
            ]
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "New Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [8_912],
                    inferredTitleBarStyle: nil,
                    frame: targetFrame,
                    allowsPublicAXRecovery: true,
                    bindingConfidenceOverride: .inferred,
                    bindingCandidateCount: 1
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID])
    }

    @MainActor
    func testRuntimeActivatorDoesNotUseRelatedCGSiblingByTitleWhenFullscreenHostFocusCannotVerify() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        let unrelatedAXWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        activator.currentAXWindowsOverride = { _ in [unrelatedAXWindow] }
        activator.axWindowTitleOverride = { _ in "Unrelated Window" }
        activator.axWindowFrameOverride = { _ in CGRect(x: 300, y: 300, width: 500, height: 300) }
        activator.focusAXWindowOverride = { _, _, _ in
            XCTFail("Unmatched public AX windows should not be focused")
            return true
        }

        let targetFrame = CGRect(x: 0, y: 37, width: 1_728, height: 1_080)
        let relatedFrame = CGRect(x: 0, y: 195, width: 1_728, height: 270)
        let targetCGWindowID: CGWindowID = 245_707
        let relatedCGWindowID: CGWindowID = 245_708
        var focusedCGWindowIDs: [CGWindowID] = []
        activator.focusCGWindowOverride = { app, cgWindowID in
            XCTAssertEqual(app.processIdentifier, currentApp.processIdentifier)
            focusedCGWindowIDs.append(cgWindowID)
            return true
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: relatedCGWindowID,
                    title: "Chrome Fullscreen Tab",
                    bounds: relatedFrame,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1
                ),
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Chrome Fullscreen Tab",
                    bounds: targetFrame,
                    isOnscreen: false,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Chrome Fullscreen Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [7_104],
                    inferredTitleBarStyle: nil,
                    frame: targetFrame,
                    allowsPublicAXRecovery: true,
                    bindingConfidenceOverride: .inferred,
                    bindingCandidateCount: 1
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID])
    }

    @MainActor
    func testRuntimeActivatorUsesRelatedAXSiblingWhenFullscreenHostFocusCannotVerify() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        let relatedAXWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let unrelatedAXWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let relatedPointer = Unmanaged.passUnretained(relatedAXWindow).toOpaque()
        let unrelatedPointer = Unmanaged.passUnretained(unrelatedAXWindow).toOpaque()

        let previousExactBridgeOverride = AXWindowInspector.cgWindowIDOverrideForTesting
        AXWindowInspector.cgWindowIDOverrideForTesting = { window in
            let pointer = Unmanaged.passUnretained(window).toOpaque()
            if pointer == relatedPointer {
                return 245_809
            }
            if pointer == unrelatedPointer {
                return 245_810
            }
            return nil
        }
        defer {
            AXWindowInspector.cgWindowIDOverrideForTesting = previousExactBridgeOverride
        }

        activator.currentAXWindowsOverride = { _ in [unrelatedAXWindow, relatedAXWindow] }
        activator.axWindowTitleOverride = { window in
            let pointer = Unmanaged.passUnretained(window).toOpaque()
            if pointer == relatedPointer {
                return "Chrome Fixture"
            }
            return "Chrome Normal Tab"
        }
        activator.axWindowFrameOverride = { window in
            let pointer = Unmanaged.passUnretained(window).toOpaque()
            if pointer == relatedPointer {
                return CGRect(x: 0, y: 74, width: 1_728, height: 165)
            }
            return CGRect(x: 384, y: 258, width: 960, height: 640)
        }

        let targetFrame = CGRect(x: 0, y: 37, width: 1_728, height: 1_080)
        let targetCGWindowID: CGWindowID = 245_808
        let relatedCGWindowID: CGWindowID = 245_809
        let unrelatedCGWindowID: CGWindowID = 245_810
        var focusedCGWindowIDs: [CGWindowID] = []
        activator.focusCGWindowOverride = { app, cgWindowID in
            XCTAssertEqual(app.processIdentifier, currentApp.processIdentifier)
            focusedCGWindowIDs.append(cgWindowID)
            return true
        }

        var focusedWindowPointers: [UnsafeMutableRawPointer] = []
        activator.focusAXWindowOverride = { window, restoreIfMinimized, _ in
            XCTAssertFalse(restoreIfMinimized)
            focusedWindowPointers.append(Unmanaged.passUnretained(window).toOpaque())
            return true
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            let targetIsVisible = focusedWindowPointers.last == relatedPointer
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Chrome Fullscreen Tab",
                    bounds: targetFrame,
                    isOnscreen: targetIsVisible,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [7_120]
                ),
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: relatedCGWindowID,
                    title: "Chrome Fixture",
                    bounds: CGRect(x: 0, y: 74, width: 1_728, height: 165),
                    isOnscreen: targetIsVisible,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [7_120]
                ),
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: unrelatedCGWindowID,
                    title: "Chrome Normal Tab",
                    bounds: CGRect(x: 384, y: 258, width: 960, height: 640),
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [1]
                )
            ]
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Chrome Fullscreen Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [7_120],
                    inferredTitleBarStyle: nil,
                    frame: targetFrame,
                    allowsPublicAXRecovery: true,
                    bindingConfidenceOverride: .inferred,
                    bindingCandidateCount: 1
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID])
        XCTAssertEqual(focusedWindowPointers, [relatedPointer])
    }

    @MainActor
    func testRuntimeActivatorUsesSameSpaceCGSurfaceWhenFullscreenHostFocusCannotVerify() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        activator.currentAXWindowsOverride = { _ in [] }
        activator.focusAXWindowOverride = { _, _, _ in
            XCTFail("CG same-space activation should not synthesize an AX focus")
            return true
        }

        let targetFrame = CGRect(x: 0, y: 37, width: 1_728, height: 1_080)
        let targetCGWindowID: CGWindowID = 245_811
        let sameSpaceCGWindowID: CGWindowID = 245_812
        let otherSpaceCGWindowID: CGWindowID = 245_813
        var focusedCGWindowIDs: [CGWindowID] = []
        activator.focusCGWindowOverride = { app, cgWindowID in
            XCTAssertEqual(app.processIdentifier, currentApp.processIdentifier)
            focusedCGWindowIDs.append(cgWindowID)
            return true
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            let targetIsVisible = focusedCGWindowIDs.last == sameSpaceCGWindowID
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: sameSpaceCGWindowID,
                    title: nil,
                    bounds: CGRect(x: 0, y: 37, width: 1_728, height: 44),
                    isOnscreen: targetIsVisible,
                    alpha: 0.0,
                    storeType: 1,
                    spaceIDs: [7_128]
                ),
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: otherSpaceCGWindowID,
                    title: nil,
                    bounds: CGRect(x: 0, y: 37, width: 1_728, height: 44),
                    isOnscreen: false,
                    alpha: 0.0,
                    storeType: 1,
                    spaceIDs: [7_124]
                ),
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Chrome Fullscreen Tab",
                    bounds: targetFrame,
                    isOnscreen: targetIsVisible,
                    alpha: 1.0,
                    storeType: 1,
                    spaceIDs: [7_128]
                )
            ]
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Chrome Fullscreen Tab",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [7_128],
                    inferredTitleBarStyle: nil,
                    frame: targetFrame,
                    allowsPublicAXRecovery: true,
                    bindingConfidenceOverride: .inferred,
                    bindingCandidateCount: 1
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID, sameSpaceCGWindowID])
    }

    @MainActor
    func testRuntimeActivatorUsesCGWindowBridgeThenAXFocusForSpaceTargetWithHandle() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        var requestActivationCallCount = 0
        activator.requestActivationOverride = { _, completion in
            requestActivationCallCount += 1
            completion?(currentApp)
        }
        let wrapperWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        var focusEvents: [String] = []
        activator.focusAXWindowOverride = { window, restoreIfMinimized, _ in
            XCTAssertTrue(CFEqual(window, wrapperWindow))
            XCTAssertFalse(restoreIfMinimized)
            focusEvents.append("ax")
            return true
        }

        let targetFrame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let targetCGWindowID: CGWindowID = 245_909
        var focusedCGWindowIDs: [CGWindowID] = []
        activator.focusCGWindowOverride = { app, cgWindowID in
            XCTAssertEqual(app.processIdentifier, currentApp.processIdentifier)
            focusedCGWindowIDs.append(cgWindowID)
            focusEvents.append("cg")
            return true
        }
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Fullscreen Content",
                    bounds: targetFrame,
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Fullscreen Content",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [2],
                    inferredTitleBarStyle: nil,
                    activationHandleID: "ax:\(currentApp.processIdentifier):wrapper",
                    axWindow: wrapperWindow,
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

        XCTAssertEqual(requestActivationCallCount, 0)
        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID])
        XCTAssertEqual(focusEvents, ["cg", "ax"])
    }

    @MainActor
    func testRuntimeActivatorRetriesCGWindowBridgeUntilSpaceTargetBecomesVisible() async {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = [20_000_000]

        var requestActivationCallCount = 0
        activator.requestActivationOverride = { _, completion in
            requestActivationCallCount += 1
            completion?(currentApp)
        }

        let targetFrame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let targetCGWindowID: CGWindowID = 245_404
        var focusedCGWindowIDs: [CGWindowID] = []
        activator.focusCGWindowOverride = { _, cgWindowID in
            focusedCGWindowIDs.append(cgWindowID)
            return true
        }

        let visibilitySettled = expectation(description: "cg bridge retry sees target window onscreen")
        var didFulfillVisibilitySettled = false
        var cgWindowReadCount = 0
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            cgWindowReadCount += 1
            let isVisible = focusedCGWindowIDs.count >= 2
            if isVisible, !didFulfillVisibilitySettled {
                didFulfillVisibilitySettled = true
                visibilitySettled.fulfill()
            }
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "CG Bridge Target",
                    bounds: targetFrame,
                    isOnscreen: isVisible,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "CG Bridge Target",
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
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        await fulfillment(of: [visibilitySettled], timeout: 1.0)
        XCTAssertEqual(requestActivationCallCount, 0)
        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID, targetCGWindowID])
        XCTAssertGreaterThanOrEqual(cgWindowReadCount, 2)
    }

    @MainActor
    func testRuntimeActivatorFocusesCGOnlySpaceTargetThroughPublicAXRecovery() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }

        var requestActivationCallCount = 0
        activator.requestActivationOverride = { app, completion in
            requestActivationCallCount += 1
            completion?(app)
        }

        let targetFrame = CGRect(x: 160, y: 140, width: 960, height: 680)
        let targetCGWindowID: CGWindowID = 240_101
        let recoveredWindow = AXUIElementCreateApplication(currentApp.processIdentifier)
        let recoveredPointer = Unmanaged.passUnretained(recoveredWindow).toOpaque()
        activator.currentAXWindowsOverride = { _ in [recoveredWindow] }
        activator.axWindowTitleOverride = { window in
            guard Unmanaged.passUnretained(window).toOpaque() == recoveredPointer else { return nil }
            return "Shared Doc"
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
                    title: "Shared Doc",
                    bounds: targetFrame,
                    isOnscreen: true,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        var focusedWindowPointers: [UnsafeMutableRawPointer] = []
        activator.focusAXWindowOverride = { window, restoreIfMinimized, _ in
            XCTAssertFalse(restoreIfMinimized)
            focusedWindowPointers.append(Unmanaged.passUnretained(window).toOpaque())
            return true
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Shared Doc",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [1],
                    inferredTitleBarStyle: nil,
                    frame: targetFrame,
                    allowsPublicAXRecovery: true,
                    bindingConfidenceOverride: .inferred,
                    bindingCandidateCount: 1
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(requestActivationCallCount, 0)
        XCTAssertEqual(focusedWindowPointers, [recoveredPointer])
    }

    @MainActor
    func testRuntimeActivatorReportsCGOnlySpaceTargetVisibleAfterAXRecoveryScan() {
        let currentApp = NSRunningApplication.current
        let appID = currentApp.bundleIdentifier ?? "pid:\(currentApp.processIdentifier)"
        let activator = RuntimeActivator()
        activator.activateCurrentAppIfNeededOverride = { _ in false }
        activator.focusRecoveryRetryDelaysNanoseconds = []

        let targetFrame = CGRect(x: 0, y: 38, width: 1_728, height: 1_079)
        let targetCGWindowID: CGWindowID = 245_505
        var focusedCGWindowIDs: [CGWindowID] = []
        activator.focusCGWindowOverride = { app, cgWindowID in
            XCTAssertEqual(app.processIdentifier, currentApp.processIdentifier)
            focusedCGWindowIDs.append(cgWindowID)
            return true
        }

        var didScanAXRecovery = false
        activator.currentAXWindowsOverride = { app in
            XCTAssertEqual(app.processIdentifier, currentApp.processIdentifier)
            didScanAXRecovery = true
            return []
        }
        activator.focusAXWindowOverride = { _, _, _ in
            XCTFail("CG-only target should verify once the target CG window becomes visible")
            return true
        }

        var visibilityChecks: [Bool] = []
        activator.currentCGWindowsOverride = { pid in
            XCTAssertEqual(pid, currentApp.processIdentifier)
            let isVisible = didScanAXRecovery
            visibilityChecks.append(isVisible)
            return [
                RuntimeSnapshotProvider.CGWindowEntry(
                    id: targetCGWindowID,
                    title: "Late Visible Target",
                    bounds: targetFrame,
                    isOnscreen: isVisible,
                    alpha: 1.0,
                    storeType: 1
                )
            ]
        }

        var verifiedCGWindowIDs: [CGWindowID?] = []
        activator.windowFocusVerifiedHandler = { _, _, _, cgWindowID, _, _, _ in
            verifiedCGWindowIDs.append(cgWindowID)
        }

        let windowID = "cg:\(currentApp.processIdentifier):\(targetCGWindowID)"
        let context = RuntimeAppContext(
            appID: appID,
            runningApp: currentApp,
            windowsByID: [
                windowID: RuntimeWindowContext(
                    id: windowID,
                    title: "Late Visible Target",
                    isMinimized: false,
                    ownerPID: currentApp.processIdentifier,
                    cgWindowID: targetCGWindowID,
                    spaceIDs: [7_136],
                    inferredTitleBarStyle: nil,
                    frame: targetFrame,
                    allowsPublicAXRecovery: true,
                    bindingConfidenceOverride: .inferred,
                    bindingCandidateCount: 1
                )
            ]
        )

        activator.activate(
            target: .window(appID: appID, windowID: windowID, restoreIfMinimized: false),
            contextsByID: [appID: context]
        )

        XCTAssertEqual(focusedCGWindowIDs, [targetCGWindowID])
        XCTAssertEqual(visibilityChecks, [false, true])
        XCTAssertEqual(verifiedCGWindowIDs, [targetCGWindowID])
    }

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
                    allowsPublicAXRecovery: true,
                    lastConfirmationSource: .publicExactMatch
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
