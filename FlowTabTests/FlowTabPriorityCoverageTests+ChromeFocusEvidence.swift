import AppKit
import CoreGraphics
import XCTest
@testable import FlowTab

extension FlowTabPriorityCoverageTests {
    func testChromeFocusBridgeScriptRequestsThenReadsExactFrontWindowImmediately() {
        let script = RuntimeChromeWindowFocusBridge.focusWindowScriptForTesting(
            windowID: 12_345
        )
        let focusCommand = "set index of window id targetWindowID to 1"
        let readbackCommand = "return id of front window as text"

        XCTAssertTrue(script.contains("set targetWindowID to 12345"))
        XCTAssertEqual(script.components(separatedBy: focusCommand).count - 1, 2)
        XCTAssertFalse(script.contains("delay "))
        guard
            let finalFocusCommand = script.range(
                of: focusCommand,
                options: .backwards
            ),
            let readback = script.range(of: readbackCommand)
        else {
            return XCTFail("Expected focus command followed by exact readback")
        }
        XCTAssertLessThan(finalFocusCommand.upperBound, readback.lowerBound)
        XCTAssertNotNil(NSAppleScript(source: script))
    }

    func testChromeFocusBridgeAcceptsOnlyExactFrontWindowReadback() {
        var executedScript = ""
        let accepted = RuntimeChromeWindowFocusBridge.focusWindow(
            windowID: 12_345,
            browser: .chrome
        ) { source in
            executedScript = source
            return RuntimeChromeWindowFocusBridge.ScriptExecutionResult(
                value: "12345",
                error: nil
            )
        }
        let mismatched = RuntimeChromeWindowFocusBridge.focusWindow(
            windowID: 12_345,
            browser: .chrome
        ) { _ in
            RuntimeChromeWindowFocusBridge.ScriptExecutionResult(
                value: "67890",
                error: nil
            )
        }

        XCTAssertTrue(executedScript.contains("set targetWindowID to 12345"))
        XCTAssertTrue(accepted.accepted)
        XCTAssertEqual(accepted.frontWindowID, 12_345)
        XCTAssertNil(accepted.error)
        XCTAssertFalse(mismatched.accepted)
        XCTAssertEqual(mismatched.frontWindowID, 67_890)
        XCTAssertNil(mismatched.error)
    }

    func testChromeFocusBridgeReportsUnavailableReadbackEvidence() {
        let executionError = RuntimeChromeWindowFocusBridge.focusWindow(
            windowID: 12_345,
            browser: .chrome
        ) { _ in
            RuntimeChromeWindowFocusBridge.ScriptExecutionResult(
                value: nil,
                error: "apple-event-not-authorized"
            )
        }
        let emptyReadback = RuntimeChromeWindowFocusBridge.focusWindow(
            windowID: 12_345,
            browser: .chrome
        ) { _ in
            RuntimeChromeWindowFocusBridge.ScriptExecutionResult(
                value: nil,
                error: nil
            )
        }
        let invalidReadback = RuntimeChromeWindowFocusBridge.focusWindow(
            windowID: 12_345,
            browser: .chrome
        ) { _ in
            RuntimeChromeWindowFocusBridge.ScriptExecutionResult(
                value: "front-window-unknown",
                error: nil
            )
        }

        XCTAssertFalse(executionError.accepted)
        XCTAssertNil(executionError.frontWindowID)
        XCTAssertEqual(executionError.error, "apple-event-not-authorized")
        XCTAssertFalse(emptyReadback.accepted)
        XCTAssertEqual(emptyReadback.error, "front-window-readback-empty")
        XCTAssertFalse(invalidReadback.accepted)
        XCTAssertEqual(
            invalidReadback.error,
            "front-window-readback-invalid:front-window-unknown"
        )
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
            RuntimeCGWindowEntry(
                id: 455,
                title: "Inbox - Gmail",
                bounds: frame,
                isOnscreen: false,
                alpha: 1,
                storeType: 1
            ),
            RuntimeCGWindowEntry(
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
            RuntimeCGWindowEntry(
                id: 455,
                title: nil,
                bounds: frame,
                isOnscreen: false,
                alpha: 1,
                storeType: 1
            ),
            RuntimeCGWindowEntry(
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
}
